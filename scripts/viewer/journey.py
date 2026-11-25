"""The fixed C1 browser journey. All chain access here uses the launcher's owned IPC."""
import secrets
import threading
from dataclasses import dataclass
from decimal import Decimal

from web3 import Web3
from web3.logs import DISCARD

from artifacts import fixture
from statement import split_delta


@dataclass(frozen=True)
class Step:
    previous: tuple
    actor: str
    at: int
    label: str


STEPS = {
    "activate": Step(("funded",), "treasury", 2000, "Activate the agreement"),
    "trade": Step(("activate",), "trader", 2120, "Trade inside the range at +120 s"),
    "claim40": Step(("trade",), "manager", 2120, "Claim the first 40 B"),
    "checkpoint": Step(("claim40",), "treasury", 2180, "Checkpoint service at +180 s"),
    "block": Step(("checkpoint",), "fixture", 2180, "Block the escrow-to-manager route"),
    "failedClaim": Step(("block",), "manager", 2180, "Attempt the remaining 20 B claim"),
    "terminate": Step(("failedClaim",), "treasury", 2180, "Terminate with payment blocked"),
    "revoked": Step(("terminate",), "manager", 2181, "Attempt a revoked liquidity removal"),
    "remove": Step(("revoked",), "treasury", 2182, "Remove liquidity and collect fees"),
    "withdraw": Step(("remove",), "treasury", 2183, "Withdraw both principal assets"),
    "refund": Step(("withdraw",), "treasury", 2184, "Collect the unearned 40 B refund"),
    "restore": Step(("refund",), "fixture", 2185, "Restore the manager payment route"),
    "claim20": Step(("restore",), "manager", 2186, "Claim the preserved 20 B"),
    "repeatClaim": Step(("claim20",), "manager", 2187, "Repeat the settled claim"),
    "repeatRefund": Step(("repeatClaim",), "treasury", 2188, "Repeat the settled refund"),
    "prepareRange": Step(("activate",), "treasury", 2030, "Manager journey: checkpoint the seed after 30 s"),
    "rerange": Step(("prepareRange",), "manager", 2031, "Extend the position to [−180, 180)"),
    "rangeSwap": Step(("rerange",), "trader", 2090, "Offer 700 B for A up to tick 120"),
    "rangeClose": Step(("rangeSwap",), "treasury", 2180, "Terminate the extended position period"),
    "rangeExit": Step(("rangeClose",), "treasury", 2182, "Remove the extended position and collect fees"),
    "rangeWithdraw": Step(("rangeExit",), "treasury", 2183, "Withdraw both vault assets to treasury"),
    "interrupt": Step(("activate",), "trader", 2090, "Alternate path: interrupt service at +90 s"),
    "return": Step(("interrupt",), "trader", 2210, "Return the pool to the opening band"),
    "shortClose": Step(("activate", "interrupt"), "treasury", 2180, "End the short preview at +180 s"),
    "returnClose": Step(("return",), "treasury", 2240, "Close the recovered position at +240 s"),
}
CLOSED = {"terminate", "revoked", "remove", "withdraw", "refund", "restore", "claim20",
          "repeatClaim", "repeatRefund", "shortClose", "returnClose", "rangeClose", "rangeExit", "rangeWithdraw"}


class Conflict(ValueError):
    pass


def check(condition, message):
    if not condition:
        raise Conflict(message)


def ledger(run, block):
    def read(fn):
        return fn.call(block_identifier=block)
    def pair(addr):
        return [read(t.functions.balanceOf(addr)) for t in (run.a, run.b)]
    return {
        "q": read(run.hook.functions.projectedSeconds()), "earned": read(run.esc.functions.earned()),
        "claimed": read(run.esc.functions.claimed()), "reserved": read(run.esc.functions.reserved()),
        "refunded": read(run.esc.functions.refunded()), "refundable": read(run.esc.functions.refundable()),
        "escrowB": read(run.b.functions.balanceOf(run.esc.address)),
        "managerB": read(run.b.functions.balanceOf(run.actors["manager"])),
        "vault": pair(run.v.address), "treasury": pair(run.owner),
        "liquidity": read(run.v.functions.positionLiquidity()),
        "qualification": list(read(run.hook.functions.qualification()))
    }


def amount(n):
    return format(Decimal(n) / 1_000_000, 'f')


def core_position(r, edge, salt, block):
    return r.router.functions.position(r.key, r.v.address, -edge, edge, fixture.word(salt)).call(block_identifier=block)


def expected_position(r, edge, salt):
    return Web3.keccak(r.w.codec.encode(["bytes32", "address", "int24", "int24", "bytes32"],
                       [r.hook.functions.poolId().call(), r.v.address, -edge, edge, fixture.word(salt)]))


def bounded_rerange(r, displayed_id, n):
    old = expected_position(r, 120, 1)
    check(displayed_id == Web3.to_hex(old) and r.v.functions.positionId().call(block_identifier=n) == old,
          "Displayed seed position is stale. Refresh this run.")
    price, tick, pool_l, owned, *_ = core_position(r, 120, 1, n)
    check((price, tick, pool_l, owned) == (1 << 96, 0, fixture.L, fixture.L)
          and core_position(r, 180, 2, n)[3] == 0, "Expected an undisturbed parity seed.")
    # Parity execution only. Each token has a separate gross input cap and principal output floor.
    bounds = (r.h, 2030, 2040, 0, 1, 900*fixture.UNIT, 900*fixture.UNIT, 598*fixture.UNIT, 598*fixture.UNIT)
    fn = r.v.functions.rerange(old, -180, 180, fixture.L, bounds)
    # The exact call exercises both unlocks against actual core liquidity, idle inventory and C1 limits.
    fn.call({"from": r.actors["manager"]}, block_identifier=n)
    return fn


def reconciled_rerange(r, receipt, before, after):
    n = receipt.blockNumber
    new = expected_position(r, 180, 2)
    check(core_position(r, 120, 1, n)[3] == 0 and core_position(r, 180, 2, n)[2:4] == [fixture.L, fixture.L]
          and r.v.functions.positionId().call(block_identifier=n) == new, "Core position replacement mismatch.")
    legs = [ev["args"] for ev in r.v.events.PositionAdjusted().process_receipt(receipt, errors=DISCARD)]
    check([(x["kind"], x["lower"], x["upper"], x["salt"], x["liquidity"]) for x in legs]
          == [(3, -120, 120, fixture.word(1), 0), (3, -180, 180, fixture.word(2), fixture.L)],
          "Unexpected rerange legs.")
    for i in (0, 1):
        delta = sum(split_delta(x["principal"])[i] + split_delta(x["fees"])[i] for x in legs)
        check(after["vault"][i]-before["vault"][i] == delta, "Idle inventory differs from rerange settlement.")
    check(before["q"] == 30 and after["q"] == 31 and after["qualification"][0]
          and after["escrowB"] == before["escrowB"] == fixture.BUDGET
          and r.v.functions.lastAdjustment().call(block_identifier=n) == 2031, "Service, custody or cooldown mismatch.")
    removed = split_delta(legs[0]["principal"])
    added = split_delta(legs[1]["principal"])
    return (f"Vault seed {Web3.to_hex(expected_position(r, 120, 1))} retired with zero L. "
            f"Salt 2 holds {fixture.L:,} L under {Web3.to_hex(new)}. "
            f"Removed {amount(removed[0])} A and {amount(removed[1])} B; "
            f"added {amount(-added[0])} A and {amount(-added[1])} B. "
            f"Idle {amount(after['vault'][0])} A and {amount(after['vault'][1])} B. "
            "31 qualifying seconds preserved; next eligible adjustment at 2061 s.")


class Journey:
    def __init__(self, run, manifest, verify):
        self.run, self.manifest, self.verify = run, manifest, verify
        self.lock = threading.Lock()
        self.stage = "funded"
        self.csrf = secrets.token_urlsafe(32)
        self.history = []
        self.problem = None
        self.head = run.w.eth.get_block("latest")
        self.closing = False

    def status(self):
        return {"runId": self.manifest["runId"], "csrf": self.csrf, "stage": self.stage,
                "version": len(self.history), "head": self.head.number, "problem": self.problem,
                "actions": [{"id": key, "actor": s.actor, "label": s.label} for key, s in STEPS.items()
                            if self.stage in s.previous and not self.problem and not self.closing],
                "receipts": self.history.copy()}

    def validate(self, body):
        check(not self.closing, "This run is closing.")
        check(body["runId"] == self.manifest["runId"], "Run changed. Refresh the agreement.")
        check(type(body["version"]) is int and body["version"] == len(self.history),
              "Action already handled or stage changed. Refresh the receipts.")
        self.verify()
        r = self.run
        check(r.w.eth.get_block("latest").hash == self.head.hash, "Owned chain head changed. Inspect the launcher before continuing.")
        expected_phase = 2 if self.stage == "funded" else 5 if self.stage in CLOSED else 4
        check(r.v.functions.state().call() == expected_phase, "Onchain lifecycle differs from the expected stage.")

    def call(self, action, body):
        r = self.run
        if action == "activate":
            return r.v.functions.activate(r.h)
        if action == "rerange":
            return bounded_rerange(r, body["positionId"], self.head.number)
        if action in ("trade", "interrupt", "return", "rangeSwap"):
            sell_a, limit = {"trade": (True, -20), "interrupt": (False, 120), "return": (True, 0), "rangeSwap": (False, 120)}[action]
            return r.router.functions.order(r.key, sell_a, 700 * fixture.UNIT, limit)
        if action in ("claim40", "claim20", "failedClaim", "repeatClaim"):
            return r.esc.functions.claim()
        if action in ("checkpoint", "prepareRange"):
            return r.hook.functions.checkpoint()
        if action in ("block", "restore"):
            return r.b.functions.setFault(r.esc.address, r.actors["manager"], 1 if action == "block" else 0)
        if action in ("terminate", "shortClose", "returnClose", "rangeClose"):
            return r.v.functions.terminate()
        if action == "revoked":
            bounds = (r.h, 2180, 2200, -240, 240, fixture.CAP, fixture.CAP, 0, 0)
            return r.v.functions.remove(r.v.functions.positionId().call(), fixture.L // 4, bounds)
        if action in ("remove", "rangeExit"):
            return r.v.functions.exitLiquidity()
        if action in ("withdraw", "rangeWithdraw"):
            return r.v.functions.withdrawIdle()
        if action in ("refund", "repeatRefund"):
            return r.esc.functions.refund()
        raise Conflict("Unknown local action.")

    def perform(self, body):
        self.validate(body)
        action = body["action"]
        step = STEPS.get(action)
        check(not self.problem and step and self.stage in step.previous, "Action unavailable at this stage.")
        r = self.run
        actor = r.owner if step.actor == "fixture" else r.actors[step.actor]
        fn = self.call(action, body)
        before = ledger(r, self.head.number)
        proof = None
        if action == "revoked":
            # Identical sender, calldata, position, tick envelope and valid window before close.
            proof = self.history[-2]["block"]  # The failed claim immediately preceding termination.
            fn.call({"from": actor}, block_identifier=proof)

        # Once submission starts, an uncertain result blocks further steps, including retries.
        self.problem = "Submission or reconciliation incomplete. Inspect this run before resetting."
        r.rpc("evm_setNextBlockTimestamp", [step.at])
        tx = fn.transact({"from": actor, "gas": 15_000_000, "gasPrice": 10**10})
        receipt = r.w.eth.wait_for_transaction_receipt(tx, timeout=10)
        block = r.w.eth.get_block(receipt.blockNumber)
        record = {"action": action, "label": step.label, "actor": step.actor, "sender": actor,
                  "target": fn.address, "hash": Web3.to_hex(tx), "block": block.number,
                  "time": block.timestamp, "success": bool(receipt.status), "detail": "Awaiting reconciliation."}
        self.history = [*self.history, record]
        self.head = block
        after = ledger(r, block.number)
        check(block.timestamp == step.at, "Unexpected transaction timestamp.")
        if not receipt.status:
            trace = r.rpc("debug_traceTransaction", [record["hash"], {"tracer": "callTracer"}])
            output = trace.get("output", "").lower()
            record["revertData"] = output
            expected = {"failedClaim": "TransferFailed(address)", "revoked": "InvalidPeriod()"}.get(action)
            check(expected is not None, "Unexpected mined revert. Inspect the receipt.")
            encoded = Web3.to_hex(Web3.keccak(text=expected)[:4])
            if action == "failedClaim":
                encoded += r.b.address[2:].lower().zfill(64)
            check(output == encoded and before == after, "Unexpected revert data or changed rights.")
            if action == "failedClaim":
                transfer = r.b.encode_abi("transfer", args=[actor, 20 * fixture.UNIT])
                reason = "0x08c379a0" + r.w.codec.encode(["string"], ["blocked route"]).hex()
                check(any(c.get("from", "").lower() == r.esc.address.lower()
                          and c.get("to", "").lower() == r.b.address.lower()
                          and c.get("input", "").lower() == transfer.lower()
                          and c.get("error") and c.get("output", "").lower() == reason
                          for c in trace.get("calls", [])), "Expected blocked token transfer missing from trace.")
            record["error"] = expected
            record["detail"] = ("Escrow-to-manager transfer failed for mock B. Rights and balances were unchanged."
                                if proof is None else
                                f"Identical manager call succeeded in simulation at active block {proof}. Position and rights were unchanged.")
        else:
            check(action not in ("failedClaim", "revoked"), "An intended onchain rejection unexpectedly succeeded.")
            record["detail"] = self.reconcile(action, receipt, before, after)
        # Transport ERC-20 base units without converting through JavaScript floating point.
        record["balances"] = {key: str(after[key]) for key in
                              ("earned", "claimed", "reserved", "refundable", "refunded", "escrowB")}
        if action == "activate":
            # Preserve the viewer's explicit one-second observation after the activation receipt.
            r.rpc("evm_setNextBlockTimestamp", [2001])
            r.rpc("evm_mine", [])
            self.head = r.w.eth.get_block("latest")
        self.stage = action
        self.problem = None
        return self.status()

    def reconcile(self, action, receipt, before, after):
        r = self.run
        check(after["earned"] == after["q"] * fixture.BUDGET // 300 and
              after["claimed"] == after["managerB"] and after["reserved"] == after["earned"] - after["claimed"] and
              after["escrowB"] == fixture.BUDGET - after["claimed"] - after["refunded"], "Ledger mismatch.")
        if action in ("claim40", "claim20", "repeatClaim"):
            delta = after["managerB"] - before["managerB"]
            check(delta == {"claim40": 40, "claim20": 20, "repeatClaim": 0}[action] * fixture.UNIT,
                  "Manager receipt differs from the expected entitlement.")
            return f"Manager received {amount(delta)} B."
        if action in ("refund", "repeatRefund"):
            delta = after["treasury"][1] - before["treasury"][1]
            check(delta == (40 * fixture.UNIT if action == "refund" else 0) and
                  after["escrowB"] == after["reserved"], "Refund or reserve mismatch.")
            return f"Treasury received {amount(delta)} B. Escrow retained {amount(after['escrowB'])} B."
        if action in ("remove", "rangeExit"):
            event, = r.v.events.LiquidityExited().process_receipt(receipt, errors=DISCARD)
            args = event["args"]
            for i in (0, 1):
                check(after["vault"][i] - before["vault"][i] == args[f"principal{i}"] + args[f"fees{i}"],
                      "Core removal and vault receipt differ.")
            check(after["liquidity"] == 0 and after["escrowB"] == before["escrowB"], "Removal mismatch.")
            return (f"Vault received principal {amount(args['principal0'])} A and {amount(args['principal1'])} B, "
                    f"plus LP fees {amount(args['fees0'])} A and {amount(args['fees1'])} B.")
        if action in ("withdraw", "rangeWithdraw"):
            received = [a - b for a, b in zip(after["treasury"], before["treasury"])]
            check(received == before["vault"] and after["vault"] == [0, 0] and
                  after["escrowB"] == before["escrowB"], "Principal receipt mismatch.")
            suffix = " with payment blocked" if action == "withdraw" else ""
            return f"Treasury received {amount(received[0])} A and {amount(received[1])} B{suffix}."
        if action == "rerange":
            return reconciled_rerange(r, receipt, before, after)
        if action == "rangeSwap":
            n = receipt.blockNumber
            def change(token):
                balance = token.functions.balanceOf(r.trader)
                return balance.call(block_identifier=n) - balance.call(block_identifier=n-1)
            used, output = -change(r.b), change(r.a)
            price, tick, _, owned, *_ = core_position(r, 180, 2, n)
            check(0 < used <= 700*fixture.UNIT and output > 0 and owned == fixture.L
                  and price <= r.router.functions.price(120).call() and after["escrowB"] == fixture.BUDGET,
                  "Unexpected trader fill or custody.")
            qualified = "qualifies" if after["qualification"][0] else "does not qualify"
            return (f"Used {amount(used)} B for {amount(output)} A; {amount(700*fixture.UNIT-used)} B unspent. "
                    f"Stored tick {tick}. The [−180, 180) position {qualified}. It covers the fixed [−120, 120) "
                    f"opening band, and C1 tests the tick against the installed position. Q={after['q']} s.")
        if action == "terminate":
            check(after["q"] == 180 and after["refundable"] == 40 * fixture.UNIT and
                  after["reserved"] == 20 * fixture.UNIT and after["escrowB"] == before["escrowB"], "Close mismatch.")
            return "Service froze at 180 seconds. Escrow retained 20 B earned and 40 B refundable."
        if action in ("trade", "checkpoint", "interrupt", "return"):
            q, qualified = {"trade": (120, True), "checkpoint": (180, True), "interrupt": (90, False),
                            "return": (90, True)}[action]
            check(after["q"] == q and after["qualification"][0] == qualified, "Service observation mismatch.")
            return f"Core tick {r.position()[1]}. Qualifying seconds {q}. Position {'qualifies' if qualified else 'is outside its range'}."
        if action in ("block", "restore"):
            return ("Mock B now rejects transfers from escrow to the fixed manager." if action == "block"
                    else "Mock B restored transfers from escrow to the fixed manager.")
        return f"Confirmed at {after['q']} qualifying seconds."
