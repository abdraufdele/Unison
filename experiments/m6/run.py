"""Offline M6 runner. Uses only the fresh Anvil process it creates."""
import csv
import json
import subprocess
import tempfile
import time
from contextlib import contextmanager
from decimal import Decimal
from functools import lru_cache
from pathlib import Path

import rlp
from eth_utils import keccak, to_checksum_address
from web3 import IPCProvider, Web3

ROOT = Path(__file__).resolve().parents[2]
START, UNIT, L = 2000, 10**6, 10**11
CAP, BUDGET = 2000 * UNIT, 100 * UNIT
ZERO = to_checksum_address(bytes(20))
SOURCES = {
    "PoolManager": "PoolManager", "CustodyToken": "CustodyFixture",
    "MockOpeningReferenceAdapter": "MockOpeningReferenceAdapter",
    "AgreementVault": "AgreementVault", "ServiceHook": "ServiceHook",
    "CompensationEscrow": "CompensationEscrow",
}


@lru_cache
def artifact(name):
    path = ROOT / "out" / (SOURCES.get(name, "Comparison") + ".sol") / (name + ".json")
    compiled = json.loads(path.read_text())
    metadata = compiled["metadata"]
    settings = metadata["settings"]
    assert metadata["compiler"]["version"] == "0.8.26+commit.8a97fa7a"
    assert settings["evmVersion"] == "cancun" and settings["viaIR"]
    assert settings["optimizer"] == {"enabled": True, "runs": 200}
    for source, expected in metadata["sources"].items():
        assert source_hash(source) == expected["keccak256"], (name, source)
    return compiled


@lru_cache
def source_hash(source):
    return Web3.to_hex(keccak((ROOT / source).read_bytes()))


def word(n):
    return n.to_bytes(32, "big")


@contextmanager
def chain():
    with tempfile.TemporaryDirectory(prefix="unison-m6-") as d:
        ipc = Path(d) / "run.ipc"
        cmd = ["anvil", "--quiet", "--host", "127.0.0.1", "--port", "0", "--ipc", str(ipc),
               "--hardfork", "cancun", "--chain-id", "31337", "--timestamp", "1000"]
        with subprocess.Popen(cmd, stdout=subprocess.DEVNULL) as node:
            try:
                deadline = time.monotonic() + 10
                while not ipc.exists():
                    if node.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("owned Anvil IPC failed to start")
                    time.sleep(.05)
                w = Web3(IPCProvider(str(ipc), timeout=10))
                assert w.client_version == "anvil/v1.8.7" and w.eth.chain_id == 31337
                assert w.eth.block_number == 0 and w.eth.get_block(0).timestamp == 1000
                yield w
            finally:
                node.terminate()
                try:
                    node.wait(3)
                except subprocess.TimeoutExpired:
                    node.kill()


class Run:
    def __init__(self, w):
        self.w = w
        self.actors = dict(zip(("treasury", "manager", "trader"), w.eth.accounts[:3]))
        self.arm = self.case = "common"
        self.gas, self.orders, self.results = [], [], []
        self.core = self.deploy("PoolManager", self.owner, at=1001)
        tokens = [self.deploy("CustodyToken", at=t) for t in (1002, 1003)]
        self.a, self.b = sorted(tokens, key=lambda c: int(c.address, 16))
        self.router = self.deploy("ComparisonRouter", self.core.address, at=1004)
        for i, (token, treasury_amount) in enumerate([(self.a, CAP), (self.b, CAP + BUDGET)]):
            self.tx("fixture", "mint treasury", token.functions.mint(self.owner, treasury_amount), 1005 + 3 * i)
            self.tx("fixture", "mint trader", token.functions.mint(self.trader, 5000 * UNIT), 1006 + 3 * i)
            self.tx("trader", "approve router", token.functions.approve(self.router.address, 5000 * UNIT), 1007 + 3 * i)

    @property
    def owner(self):
        return self.actors["treasury"]

    @property
    def trader(self):
        return self.actors["trader"]

    def rpc(self, method, args):
        reply = self.w.provider.make_request(method, args)
        if "error" in reply:
            raise RuntimeError((method, reply["error"]))
        return reply["result"]

    def tx(self, payer, op, fn, at, failure=None):
        self.rpc("evm_setNextBlockTimestamp", [at])
        sender = self.actors.get(payer, self.owner)
        tx = fn.transact({"from": sender, "gas": 15_000_000, "gasPrice": 10**10})
        receipt = self.w.eth.wait_for_transaction_receipt(tx, timeout=10)
        assert self.w.eth.get_block(receipt.blockNumber).timestamp == at
        if not receipt.status:
            trace = self.rpc("debug_traceTransaction", [Web3.to_hex(tx), {"tracer": "callTracer"}])
            selector = trace.get("output", "")[:10]
            if not failure or selector != Web3.to_hex(keccak(text=failure)[:4]):
                raise AssertionError((self.arm, self.case, op, selector, trace.get("error")))
        elif failure:
            raise AssertionError((op, "unexpected success"))
        self.gas.append(dict(arm=self.arm, scenario=self.case, payer=payer, operation=op, second=at - START,
                             status=receipt.status, gas=receipt.gasUsed))
        return receipt

    def contract(self, name, address=None):
        data = artifact(name)
        return self.w.eth.contract(address=address, abi=data["abi"], bytecode=data["bytecode"]["object"])

    def deploy(self, name, *args, at):
        payer = "fixture" if name == "CustodyToken" else "treasury"
        receipt = self.tx(payer, "deploy " + name, self.contract(name).constructor(*args), at)
        return self.contract(name, receipt.contractAddress)

    def balances(self, who):
        return tuple(t.functions.balanceOf(who).call() for t in (self.a, self.b))

    def setup(self, arm):
        self.arm, self.case = arm, "setup"
        self.edge, self.salt = 120, 1
        self.esc = self.hook = None
        manager = self.actors["manager"]
        pm, a, b = self.core.address, self.a.address, self.b.address
        if arm == "C":
            adapter = self.deploy("MockOpeningReferenceAdapter", at=1901)
            factory = self.deploy("HookInstaller", at=1902)
            # Escrow and hook creation precede the vault. Bind them to its actual CREATE address.
            nonce = self.w.eth.get_transaction_count(self.owner)
            addr = to_checksum_address(keccak(rlp.encode([bytes.fromhex(self.owner[2:]), nonce + 2]))[-20:])
            self.esc = self.deploy("CompensationEscrow", addr, b, self.owner, manager, at=1903)
            init = self.contract("ServiceHook").constructor(addr, pm, a, b).data_in_transaction
            prefix = b"\xff" + bytes.fromhex(factory.address[2:])
            code_hash = Web3.keccak(hexstr=init)
            for n in range(1_000_000):
                digest = keccak(prefix + word(n) + code_hash)
                if int.from_bytes(digest[-2:], "big") & 0x3fff == 0x840:
                    break
            else:
                raise AssertionError("hook salt search exhausted")
            self.tx("treasury", "deploy ServiceHook", factory.functions.install(word(n), addr, pm, a, b), 1904)
            self.hook = self.contract("ServiceHook", to_checksum_address(digest[-20:]))
            bindings = (pm, a, b, self.hook.address, self.esc.address, adapter.address, adapter.address)
            self.v = self.deploy("AgreementVault", word(1), manager, bindings, at=1905)
            assert self.v.address == addr and self.hook.functions.vault().call() == addr
            obs = (adapter.address, a, b, 6, 6, 8, 100_000_000, 1981, True)
            self.tx("treasury", "publish opening", adapter.functions.publish(obs), 1981)
        elif arm == "B":
            self.v = self.deploy("Retainer", pm, a, b, manager, at=1905)
            self.esc = self.contract("RetainerEscrow", self.v.functions.escrow().call())
        else:
            self.v = self.deploy("Passive", pm, a, b, at=1905)
        self.key = (a, b, 3000, 60, self.hook.address if self.hook else ZERO)
        self.tx("treasury", "initialize pool", self.core.functions.initialize(self.key, 1 << 96), 1982)
        self.tx("treasury", "approve A", self.a.functions.approve(self.v.address, CAP), 1983)
        self.tx("treasury", "approve B", self.b.functions.approve(self.v.address, CAP + (BUDGET if self.esc else 0)), 1984)
        if self.esc:
            self.h = self.v.functions.termsHash().call()
            for t, role in enumerate(("treasury", "manager"), 1985):
                self.tx(role, "accept", self.v.functions.accept(self.h), t)
            self.tx("treasury", "fund", self.v.functions.fund(self.h), 1990)
            self.tx("treasury", "activate", self.v.functions.activate(self.h), START)
        else:
            self.tx("treasury", "seed", self.v.functions.seed(), START)
        self.pos = self.position()
        assert self.pos[:4] == [1 << 96, 0, L, L] and self.balances(self.core.address) == (598173777, 598173777)
        assert self.balances(self.trader) == (5000 * UNIT, 5000 * UNIT)
        if self.esc:
            assert self.balances(self.esc.address) == (0, BUDGET)
            assert self.balances(self.v.address) == (CAP - 598173777,) * 2
        else:
            assert self.balances(self.owner) == (CAP - 598173777, CAP - 598173777 + BUDGET)

    def position(self):
        return self.router.functions.position(self.key, self.v.address, -self.edge, self.edge, word(self.salt)).call()

    def score_to(self, t):
        t = min(t, self.end)
        sqrt, tick, pool_l, owned = self.pos[:4]
        if - self.edge <= tick < self.edge and owned >= L and 120 <= self.edge <= 240:
            assert pool_l == owned and sqrt > 0 and self.edge % 60 == 0
            self.q += t - self.last
            self.l_seconds += owned * (t - self.last)
        assert t >= self.last
        self.last = t

    def order(self, t, sell, offer, limit, label):
        self.score_to(t)
        before = self.balances(self.trader)
        old = self.pos
        self.tx("trader", label, self.router.functions.order(self.key, sell, offer, limit), START + t)
        self.pos = self.position()
        after = self.balances(self.trader)
        i, j = (0, 1) if sell else (1, 0)
        used, out = before[i]-after[i], after[j]-before[j]
        assert 0 <= used <= offer and out >= 0
        # Single LP with constant L during the order. Growth rounds down by <1 Q128 unit per step.
        growth = self.pos[6 + i]-old[6 + i]
        fee = (growth * old[3] + 2**128 - 1) // 2**128
        assert 0 <= fee <= used and self.pos[7 - i] == old[7 - i]
        limit_price = self.router.functions.price(limit).call()
        assert limit_price <= self.pos[0] <= old[0] if sell else old[0] <= self.pos[0] <= limit_price
        mark = Decimal("1.10") if self.case == "drift" and t >= 150 else Decimal(1)
        expected = used * mark if sell else used / mark
        bps = round((1 - out / expected) * 10_000, 4) if used else ""
        self.orders.append(dict(arm=self.arm, scenario=self.case, second=t, input="A" if sell else "B",
                                offer=offer, limit_tick=limit, used=used, unspent=offer - used, output=out,
                                input_fee=fee, slippage_bps=bps, tick=self.pos[1], sqrt_x96=self.pos[0], pool_L=self.pos[2]))
        if self.hook:
            assert self.hook.functions.projectedSeconds().call() == self.q

    def adjust(self, t, edge, liquidity, fail):
        self.score_to(t)
        old = self.pos
        idle = self.balances(self.v.address)
        bounds = (self.h, START + t, START + t, -240, 240, CAP, CAP, 0, 0)
        call = self.v.functions.rerange(self.v.functions.positionId().call(), -edge, edge, liquidity, bounds)
        self.tx("manager", "rerange", call, START + t, "PrincipalLimit()" if fail else None)
        if fail:
            assert self.position() == old and self.balances(self.v.address) == idle
        else:
            assert self.position()[3] == 0
            self.collected = list(old[4:6])
            self.edge, self.salt = edge, 2
            assert self.position()[3] == liquidity
        self.pos = self.position()

    def scenario(self, case):
        self.case = case
        self.q = self.l_seconds = self.last = 0
        self.end = 180 if case == "early" else 300
        self.collected = [0, 0]
        self.edge, self.salt = 120, 1
        self.pos = self.position()
        assert self.pos[:4] == [1 << 96, 0, L, L]
        self.order(90, False, (1 if case in ("flat", "early", "drift") else 700) * UNIT, 120, "outward")
        if case == "drift":
            for t in (110, 115):
                self.order(t, False, UNIT // 4, 120, "repeat")
        if case in ("feasible", "infeasible") and self.esc:
            feasible = case == "feasible"
            self.adjust(120, 180 if feasible else 240, L if feasible else 2 * L, not feasible)
        if case == "feasible":
            self.order(150, False, 50 * UNIT, 230, "follow-on")
        if case in ("flat", "interrupted", "delayed", "drift"):
            self.order(240 if case == "delayed" else 210, True,
                       (1 if case in ("flat", "drift") else 700) * UNIT, 0, "return")
        if case == "early" and self.esc:
            self.tx("manager", "interim claim", self.esc.functions.claim(), START + 120)
            assert self.balances(self.actors["manager"])[1] == 40 * UNIT
            self.fault(170, 1)
            self.tx("manager", "failed claim", self.esc.functions.claim(), START + 179, "TransferFailed(address)")
            self.tx("treasury", "terminate", self.v.functions.terminate(), START + 180)
        self.score_to(self.end)
        if case == "interrupted":
            self.order(301, True, UNIT, -120, "post-close")
        self.finish()

    def fault(self, t, mode):
        self.tx("fixture", "set payout fault", self.b.functions.setFault(self.esc.address, self.actors["manager"], mode), START + t)

    def finish(self):
        e = self.end
        # Read close rights at/after the stop on all chains, even when there is no transaction at expiry.
        if self.w.eth.get_block("latest").timestamp < START + e:
            self.rpc("evm_setNextBlockTimestamp", [START + e])
            self.rpc("evm_mine", [])
        pre = self.position()
        assert pre == self.pos
        sqrt, tick, pool_l, owned, fee_a, fee_b, _, _ = pre
        lo, hi = (self.router.functions.price(t).call() for t in (-self.edge, self.edge))
        clipped = min(hi, max(lo, sqrt))
        burn = (owned * (hi - clipped) * (1 << 96) // (hi * clipped), owned * (clipped - lo) // (1 << 96))
        fees = (self.collected[0] + fee_a, self.collected[1] + fee_b)
        if self.esc:
            idle = self.balances(self.v.address)
            paid = self.esc.functions.claimed().call()
            reserve = self.esc.functions.reserved().call()
            earned = BUDGET * (self.q if self.hook else e) // 300
            assert paid + reserve == earned
            if self.hook:
                assert self.hook.functions.projectedSeconds().call() == self.q
            self.tx("treasury", "remove", self.v.functions.exitLiquidity(), START + e + 2)
            self.tx("treasury", "withdraw", self.v.functions.withdrawIdle(), START + e + 3)
            principal = self.balances(self.owner)
            refund = BUDGET - earned
            if refund:
                self.tx("treasury", "refund", self.esc.functions.refund(), START + e + 4)
            assert self.balances(self.esc.address) == (0, reserve)
            if self.case == "early":
                self.fault(e + 5, 0)
            self.tx("manager", "final claim", self.esc.functions.claim(), START + e + 6)
            assert self.esc.functions.reserved().call() == 0 and self.balances(self.esc.address) == (0, 0)
            assert self.esc.functions.refunded().call() == refund
        else:
            ia, ib = self.balances(self.owner)
            idle = ia, ib - BUDGET
            paid = reserve = earned = refund = 0
            self.tx("treasury", "remove and receive", self.v.functions.exit(), START + e + 2)
            a, b = self.balances(self.owner)
            principal = a, b - BUDGET
        assert self.position()[2:4] == [0, 0] and self.balances(self.v.address) == (0, 0)
        assert principal == (idle[0] + burn[0] + fee_a, idle[1] + burn[1] + fee_b)
        assert self.balances(self.actors["manager"]) == (0, earned)
        treasury = self.balances(self.owner)
        assert treasury == (principal[0], principal[1] + (refund if self.esc else BUDGET))
        # Exact end-to-end token conservation, including rounding dust retained by core.
        for i in (0, 1):
            total = sum(self.balances(addr)[i] for addr in (self.owner, self.actors["manager"], self.trader, self.core.address))
            assert total == CAP + 5000 * UNIT + i * BUDGET
        mark = Decimal("1.10") if self.case == "drift" else Decimal(1)
        value = (principal[0] * mark + principal[1]) / UNIT
        treasury_value = (treasury[0] * mark + treasury[1]) / UNIT
        self.results.append(dict(
            arm=self.arm, scenario=self.case, Q=self.q, qualified_L_seconds=self.l_seconds,
            end_tick=tick, end_sqrt_x96=sqrt, pre_exit_pool_L=pool_l, owned_L=owned, edge=self.edge,
            idle_A=idle[0], idle_B=idle[1],
            burn_A=burn[0], burn_B=burn[1], fees_A=fees[0], fees_B=fees[1],
            inventory_A=principal[0], inventory_B=principal[1],
            paid_at_close=paid, reserve_at_close=reserve, final_paid=earned, refunded=refund, final_reserve=0,
            treasury_A=treasury[0], treasury_B=treasury[1], mark_B_per_A=mark,
            inventory_value_B=value, treasury_value_B=treasury_value,
        ))


def write_rows(directory, table, rows):
    with (directory / (table + ".csv")).open("w") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def matched(run, case, arms):
    outcomes = [r for r in run.results if r["scenario"] == case and r["arm"] in arms]
    assert len(outcomes) == len(arms)
    orders = {a: [r for r in run.orders if r["scenario"] == case and r["arm"] == a] for a in arms}

    def project(rows, keys):
        return [tuple(r[k] for k in keys) for r in rows]

    intent = ("second", "input", "offer", "limit_tick")
    assert all(project(rows, intent) == project(orders["B"], intent) for rows in orders.values())
    fills = ("used", "unspent", "output", "input_fee", "slippage_bps", "tick", "sqrt_x96", "pool_L")
    for a, rows in orders.items():
        if a != "A" or case != "feasible":
            assert project(rows, fills) == project(orders["B"], fills)
    economic = ("Q", "qualified_L_seconds", "inventory_A", "inventory_B", "fees_A", "fees_B", "end_sqrt_x96")
    b = next(r for r in outcomes if r["arm"] == "B")
    assert all(project([r], economic) == project([b], economic) for r in outcomes if r["arm"] != "A" or case != "feasible")


def main(directory):
    directory.mkdir(parents=True, exist_ok=True)
    if any(directory.iterdir()):
        raise ValueError("use an empty output directory")
    with chain() as w:
        run = Run(w)
        base = run.rpc("evm_snapshot", [])
        # Prove the entire interrupted managed pair before extending the comparison.
        cases = ["interrupted", "flat", "feasible", "infeasible", "delayed", "early", "drift"]
        batches = [("B", cases[:1]), ("C", cases), ("B", cases[1:]), ("A", cases)]
        for arm, workload in batches:
            assert run.rpc("evm_revert", [base])
            base = run.rpc("evm_snapshot", [])
            n = len(run.gas)
            run.setup(arm)
            original = [r for r in run.gas[:n] if r["arm"] == arm and r["scenario"] == "setup"]
            if original:
                assert run.gas[n:] == original
                del run.gas[n:]
            active = run.rpc("evm_snapshot", [])
            for case in workload:
                assert run.rpc("evm_revert", [active])
                active = run.rpc("evm_snapshot", [])
                run.scenario(case)
                for table, rows in (("gas", run.gas), ("orders", run.orders), ("outcomes", run.results)):
                    write_rows(directory, table, rows)
                if case == cases[0] and arm == "C":
                    matched(run, case, ("B", "C"))
                    print("Interrupted managed pair matched on service, fills and inventory", flush=True)
                if arm == "A":
                    matched(run, case, ("A", "B", "C"))
                print(arm, case, "reconciled", flush=True)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    main(parser.parse_args().output)
