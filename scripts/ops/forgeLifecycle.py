"""Coordinate single-actor Solidity scripts on an owned Anvil. Only fixture setup, swaps and time use RPC controls."""

import json
import os
from pathlib import Path
import secrets
import sys
import tempfile

from web3 import Web3, IPCProvider
from deployment import sendOperation
from environment import checkNetwork, contract, loadConfig, ownedChain, require
from forgeSuite import NETWORK_SCRIPTS, deploy, invoke, runForge

ZERO = "0x" + "00" * 32
BUDGET = 100_000_000


def minedTime(w):
    return w.eth.get_block("latest").timestamp


def warp(w, target):
    require(isinstance(w.provider, IPCProvider) and target > minedTime(w), "owned chain time required")
    for method, args in (("evm_setNextBlockTimestamp", [target]), ("evm_mine", [])):
        require("error" not in w.provider.make_request(method, args), "Anvil time control failed")


def rejection(w, actors, reason, fn):
    """Require the specified pre-broadcast failure and unchanged nonces for every disposable actor."""
    before = [w.eth.get_transaction_count(a) for a in actors]
    try:
        fn()
    except ValueError as exc:
        require(reason in str(exc), f"unexpected rejection; expected {reason}: {str(exc)[-600:]}")
    else:
        raise AssertionError("expected rejection: " + reason)
    require(before == [w.eth.get_transaction_count(a) for a in actors], "rejection consumed nonce")
    print("pre-broadcast rejection:", reason, flush=True)


def scenario(w, c, directory, early):
    """Deploy the requested network script and reconcile terminal rights against independent ERC-20 receipts."""
    require(isinstance(w.provider, IPCProvider), "owned IPC required")
    treasury, manager, trader = w.eth.accounts[:3]
    actors = (treasury, manager, trader)
    directory.mkdir()
    config = directory / "config.json"
    path = directory / "deployment.json"
    c = dict(c)
    env = dict(
        os.environ,
        CONFIG=str(config),
        UNISON_TREASURY=treasury,
        UNISON_MANAGER=manager,
        RUN_ID="0x" + secrets.token_hex(32),
        CONFIRM_CHAIN=str(c["chainId"]),
    )
    fixtureReceipts = []

    def configFile():
        # No upstream endpoint is needed by Solidity. The fork itself holds the read transport.
        config.write_text(json.dumps({k: v for k, v in c.items() if k != "rpc"}))

    def fixture(fn, actor):
        r = sendOperation(w, c, fn, actor)
        fixtureReceipts.append(
            dict(
                action=getattr(fn, "fn_name", "CREATE"),
                sender=actor,
                hash=Web3.to_hex(r.transactionHash),
                status=r.status,
            )
        )
        return r

    def preflight(network, inputs=env):
        return runForge(
            w,
            c,
            "script/deploy/" + NETWORK_SCRIPTS[network] + ".s.sol",
            "preflight()",
            [],
            inputs["UNISON_TREASURY"],
            inputs,
            False,
            directory / "preflight",
        )

    configFile()
    rejection(
        w,
        actors,
        "deployment actor/run",
        lambda: runForge(
            w,
            c,
            "script/deploy/" + NETWORK_SCRIPTS[c["network"]] + ".s.sol",
            "run()",
            [],
            manager,
            env,
            False,
            directory / "wrong-deployer",
        ),
    )
    other = "local" if c["network"] != "local" else "sepolia"
    rejection(w, actors, "wrong network", lambda: preflight(other))
    rejection(
        w, actors, "deployment actor/run", lambda: preflight(c["network"], dict(env, UNISON_MANAGER=treasury))
    )
    if c["network"] == "mainnet":
        rejection(w, actors, "reviewed tokens and reference required", lambda: preflight("mainnet"))
        # Fork-only stand-ins for externally supplied dependencies. The production config stays empty.
        tokens = sorted(
            (fixture(contract(w, "DemoToken").constructor(), treasury).contractAddress for _ in range(2)),
            key=lambda a: int(a, 16),
        )
        adapter = fixture(contract(w, "DemoReference").constructor(*tokens), treasury).contractAddress
        c.update(
            treasury=treasury,
            manager=manager,
            token0=tokens[0],
            token1=tokens[1],
            adapter=adapter,
            source=adapter,
            initialSqrtPriceX96=str(1 << 96),
        )
        for k in ("token0", "token1", "adapter", "source"):
            c[k + "Hash"] = Web3.to_hex(Web3.keccak(w.eth.get_code(c[k])))
        expected = c["token1Hash"]
        c["token1Hash"] = ZERO
        configFile()
        rejection(w, actors, "dependency runtime", lambda: preflight("mainnet"))
        c["token1Hash"] = expected
        c["token0"], c["token1"] = c["token1"], c["token0"]
        configFile()
        rejection(w, actors, "C1 token order/units", lambda: preflight("mainnet"))
        c["token0"], c["token1"] = c["token1"], c["token0"]
        configFile()
    elif early and c["network"] == "local":
        c["localFaultDemo"] = True
    configFile()
    preflight(c["network"])
    if c["network"] == "local" and not early:
        simulated = deploy(w, c, directory / "simulated.json", env, False)
        require(
            simulated["status"] == "simulated" and not simulated["receipts"] and "anchor" not in simulated,
            "simulation mislabeled",
        )
    m = deploy(w, c, path, env, True)
    a = m["addresses"]
    v = contract(w, "AgreementVault", a["vault"]).functions
    h = contract(w, "ServiceHook", a["hook"]).functions
    e = contract(w, "CompensationEscrow", a["escrow"]).functions
    tokenA, tokenB = [contract(w, "CustodyToken", a[k]).functions for k in ("token0", "token1")]

    def inputs(actor):
        return dict(
            env,
            ACTOR=actor,
            TERMS=Web3.to_hex(v.termsHash().call()),
            POSITION=Web3.to_hex(v.positionId().call()),
            EXPECTED_STATE=str(v.state().call()),
            DEADLINE=str(minedTime(w) + 25),
        )

    def call(name, actor=treasury, args=(), send=True, overrides=None):
        return invoke(w, c, path, dict(inputs(actor), **(overrides or {})), name, args, send)

    call("verify", send=False)
    call("read", send=False)
    if early:
        rejection(w, actors, "stale terms/position", lambda: call("accept", overrides={"TERMS": ZERO}))
        rejection(w, actors, "wrong actor", lambda: call("accept", trader))
        rejection(
            w,
            actors,
            "operator deadline",
            lambda: call("accept", overrides={"DEADLINE": str(minedTime(w) - 1)}),
        )
        # Exercise the Solidity verifier itself on a corrupt copy without passing through the Python validator.
        bad = dict(m, create2=dict(m["create2"], flags="0x800"))
        wrong = directory / "wrong-flags.json"
        wrong.write_text(json.dumps(bad))
        rejection(
            w,
            actors,
            "recorded hook flags/plan",
            lambda: runForge(
                w,
                c,
                "script/deploy/VerifyDeployment.s.sol",
                "run()",
                [],
                treasury,
                dict(env, MANIFEST=str(wrong)),
                False,
                directory / "wrong-flags",
            ),
        )
        call("accept", manager)
        adapter = fixture(
            contract(w, "DemoReference").constructor(a["token0"], a["token1"]), treasury
        ).contractAddress
        hash_ = Web3.to_hex(Web3.keccak(w.eth.get_code(adapter)))
        ref = directory / "reference.json"
        ref.write_text(json.dumps(dict(adapter=adapter, source=adapter, adapterHash=hash_, sourceHash=hash_)))
        call("revise", overrides={"REFERENCE_CONFIG": str(ref)})
        require(
            v.managerAcceptedRevision().call() == 0 and v.revision().call() == 3, "revision retained consent"
        )
    call("accept", manager)
    call("accept")
    call("approveFunding", args=["false"])
    call("approveFunding", args=["true"])
    require(
        tokenA.allowance(treasury, a["vault"]).call() == 2_000_000_000
        and tokenB.allowance(treasury, a["vault"]).call() == 2_100_000_000,
        "funding allowance mismatch",
    )
    call("fund")
    require(
        tokenA.balanceOf(a["vault"]).call() == tokenB.balanceOf(a["vault"]).call() == 2_000_000_000
        and tokenB.balanceOf(a["escrow"]).call() == BUDGET,
        "custody wrong after funding",
    )
    if c["network"] != "mainnet":
        call("refresh")
    call("preview", send=False)
    call("preflightActivation", send=False)
    call("activate")
    start = v.start().call()
    require(v.positionLiquidity().call() == 10**11 and h.qualification().call()[0], "seed identity")
    # An independent trader takes the pool above the upper tick, then returns it to parity.
    router = fixture(contract(w, "ComparisonRouter").constructor(a["core"]), trader).contractAddress
    for token in (tokenA, tokenB):
        fixture(token.transfer(trader, 900_000_000), treasury)
        fixture(token.approve(router, 900_000_000), trader)
    order = contract(w, "ComparisonRouter", router).functions
    key = (a["token0"], a["token1"], 3000, 60, a["hook"])
    fixture(order.order(key, False, 800_000_000, 120), trader)
    outAt = minedTime(w)
    require(h.observedTick().call() == 120 and not h.qualification().call()[0], "swap failed to interrupt")
    warp(w, outAt + 12)
    fixture(order.order(key, True, 800_000_000, 0), trader)
    backAt = minedTime(w)
    require(h.qualification().call()[0], "return swap failed to restore service")
    bounds = directory / "bounds.json"

    def adjust(name, args, actor=manager, changes=None):
        time = minedTime(w)
        bounds.write_text(
            json.dumps(
                dict(
                    validFrom=time,
                    tickLower=-120,
                    tickUpper=120,
                    maxInput0=2_000_000_000,
                    maxInput1=2_000_000_000,
                    minOutput0=0,
                    minOutput1=0,
                )
            )
        )
        call(name, actor, args, overrides=dict({"BOUNDS_CONFIG": str(bounds)}, **(changes or {})))

    if early:
        warp(w, max(start + 31, minedTime(w) + 1))
        rejection(
            w, actors, "stale terms/position", lambda: adjust("remove", [1], changes={"POSITION": ZERO})
        )
        rejection(w, actors, "NotManager", lambda: adjust("remove", [1], treasury))
        rejection(w, actors, "LiquidityLimit", lambda: adjust("add", [-120, 120, 200_000_000_000]))
        adjust("add", [-120, 120, 10_000_000_000])
        warp(w, minedTime(w) + 31)
        adjust("remove", [10_000_000_000])
        old = v.positionId().call()
        warp(w, minedTime(w) + 31)
        adjust("rerange", [-180, 120, 100_000_000_000])
        require(old != v.positionId().call(), "rerange retained old position")
    warp(w, minedTime(w) + 5)
    call("checkpoint", manager)
    managerBefore = tokenB.balanceOf(manager).call()
    call("claim", manager)
    firstClaim = e.claimed().call()
    require(
        firstClaim > 0 and tokenB.balanceOf(manager).call() - managerBefore == firstClaim,
        "first manager receipt",
    )
    fault = c.get("localFaultDemo", False)
    if fault:
        fixture(tokenB.setFault(a["escrow"], manager, 1), treasury)
    if early:
        warp(w, minedTime(w) + 20)
        if fault:
            rejection(w, actors, "TransferFailed", lambda: call("claim", manager))
            # The normal script refuses the reverting transfer. Separately mine its same typed claim
            # on this fault-injected local IPC chain to check EVM rollback and receipt status.
            require(
                c["network"] == "local" and isinstance(w.provider, IPCProvider), "local fault fixture only"
            )
            failed = w.eth.wait_for_transaction_receipt(
                e.claim().transact({"from": manager, "gas": 1_000_000})
            )
            require(
                failed.status == 0
                and e.claimed().call() == firstClaim
                and tokenB.balanceOf(manager).call() == managerBefore + firstClaim,
                "failed compensation transfer changed paid balances",
            )
            fixtureReceipts.append(
                dict(
                    action="claim with blocked recipient",
                    sender=manager,
                    hash=Web3.to_hex(failed.transactionHash),
                    status=0,
                )
            )
        call("terminate")
    else:
        warp(w, v.scheduledEnd().call() + 5)
        call("finalizeExpiry", manager)
    stop = v.effectiveStop().call()
    qualifying = stop - start - (backAt - outAt)
    earned = BUDGET * qualifying // 300
    require(
        earned == e.earned().call() and h.projectedSeconds().call() == qualifying,
        "independent time reconciliation",
    )
    reserve = earned - firstClaim
    require(reserve > 0 and e.reserved().call() == reserve, "unpaid entitlement")
    call("exitLiquidity")
    idle = [t.balanceOf(a["vault"]).call() for t in (tokenA, tokenB)]
    before = [t.balanceOf(treasury).call() for t in (tokenA, tokenB)]
    call("withdrawIdle")
    received = [t.balanceOf(treasury).call() - balance for t, balance in zip((tokenA, tokenB), before)]
    require(
        idle == received and min(received) > 0 and e.reserved().call() == reserve,
        "independent principal receipt",
    )
    before = tokenB.balanceOf(treasury).call()
    call("refund")
    require(
        tokenB.balanceOf(treasury).call() - before == BUDGET - earned
        and tokenB.balanceOf(a["escrow"]).call() == reserve,
        "refund spent manager reserve",
    )
    if fault:
        fixture(tokenB.setFault(a["escrow"], manager, 0), treasury)
    call("claim", manager)
    require(
        tokenB.balanceOf(manager).call() - managerBefore == earned
        and tokenB.balanceOf(a["escrow"]).call() == 0,
        "final independent manager receipt",
    )
    call("verifySettlement", send=False)
    if c["network"] == "mainnet":
        rejection(w, actors, "reference stale/incomplete", lambda: preflight("mainnet"))
    result = dict(
        network=c["network"],
        path="early" if early else "expiry",
        creationReceipts=len(m["receipts"]),
        start=start,
        swapOut=outAt,
        swapBack=backAt,
        stop=stop,
        qualifyingSeconds=qualifying,
        paid=earned,
        firstClaim=firstClaim,
        reserveThroughRefund=reserve,
        refunded=BUDGET - earned,
        principalReceived=received,
        escrowBalance=0,
        fixtureClaimFailure=fault,
    )
    result["runId"] = m["runId"]
    result["actorAddresses"] = {"treasury": treasury, "manager": manager, "trader": trader}
    result["deploymentTransactions"] = [r["receipt"]["transactionHash"] for r in m["receipts"]]
    result["actionTransactions"] = []
    for journal in sorted(path.with_suffix(".forge").glob("*/broadcast/*/*/*-latest.json")):
        bundle = json.loads(journal.read_text())
        for tx in bundle["transactions"]:
            result["actionTransactions"].append(
                dict(action=tx["function"], sender=tx["transaction"]["from"], hash=tx["hash"])
            )
    result["fixtureReceipts"] = fixtureReceipts
    (directory / "results.json").write_text(json.dumps(result, indent=2))
    print(
        json.dumps(
            {
                k: v
                for k, v in result.items()
                if k
                not in ("actorAddresses", "actionTransactions", "deploymentTransactions", "fixtureReceipts")
            }
        ),
        flush=True,
    )
    if c["network"] == "local" and not early:
        # Exercise pre-activation cancellation on a separate correctly deployed draft.
        cancelledPath = directory / "cancelled.json"
        cancelEnv = dict(env, RUN_ID="0x" + secrets.token_hex(32))
        cancelled = deploy(w, c, cancelledPath, cancelEnv, True)
        cancelEnv.update(
            TERMS=cancelled["termsHash"],
            POSITION=ZERO,
            EXPECTED_STATE="0",
            ACTOR=treasury,
            DEADLINE=str(minedTime(w) + 30),
        )
        invoke(w, c, cancelledPath, cancelEnv, "cancel", [], True)
        invoke(w, c, cancelledPath, cancelEnv, "verifySettlement", [], False)
        print("Cancelled unfunded draft reconciled", flush=True)


def main():
    network = sys.argv[1] if len(sys.argv) > 1 else "local"
    c = loadConfig(network, None)
    root = Path(tempfile.mkdtemp(prefix="forge-lifecycle-", dir=ROOT_OPS)).resolve()
    print("Evidence", root, flush=True)
    for early in [True, False] if network == "local" else [network == "sepolia"]:
        with ownedChain(c) as w:
            checkNetwork(w, c)
            require(
                "error" not in w.provider.make_request("anvil_setBlockTimestampInterval", [1]),
                "owned chain needs repeatable block timestamps",
            )
            scenario(w, c, root / ("early" if early else "expiry"), early)


ROOT_OPS = Path(".local/ops")
if __name__ == "__main__":
    ROOT_OPS.mkdir(parents=True, exist_ok=True)
    main()
