"""Exercise real manager calls on an owned, pinned fork with explicitly disposable mock assets."""

import tempfile
from pathlib import Path
from web3 import IPCProvider, Web3
from deployment import deployAgreement, sendOperation
from environment import contract, require


# Fund, activate, trade, stop and recover against the configured official core using only owned fork signers.
def exerciseFork(w, c):
    require(isinstance(w.provider, IPCProvider), "fork rehearsal requires owned IPC")
    with tempfile.TemporaryDirectory() as d:
        m = deployAgreement(w, c, Path(d) / "fork.json", "fork-rehearsal")
        a = m["addresses"]
        t, manager = m["treasury"], m["manager"]
        v = contract(w, "AgreementVault", a["vault"]).functions
        b = contract(w, "CustodyToken", a["token1"]).functions
        terms = v.termsHash().call()
        calls = [
            (t, v.accept(terms)),
            (manager, v.accept(terms)),
            (t, contract(w, "CustodyToken", a["token0"]).functions.approve(a["vault"], 2_000_000_000)),
            (t, b.approve(a["vault"], 2_100_000_000)),
            (t, v.fund(terms)),
        ]
        for actor, fn in calls:
            sendOperation(w, c, fn, actor)
        now = w.eth.get_block("latest").timestamp
        obs = (a["adapter"], a["token0"], a["token1"], 6, 6, 8, 100_000_000, now, True)
        sendOperation(
            w, c, contract(w, "MockOpeningReferenceAdapter", a["adapter"]).functions.publish(obs), t
        )
        quote = v.preflightActivation(terms).call()
        require(quote.seed.amount0 == quote.seed.amount1 == 598173777, "unexpected parity seed")
        sendOperation(w, c, v.activate(terms), t)
        require(v.positionLiquidity().call() == 10**11, "core did not install expected seed")
        router = sendOperation(
            w, c, contract(w, "ComparisonRouter").constructor(a["core"]), t
        ).contractAddress
        sendOperation(w, c, b.mint(manager, 700_000_000), t)
        sendOperation(w, c, b.approve(router, 700_000_000), manager)
        key = (a["token0"], a["token1"], 3000, 60, a["hook"])
        sendOperation(
            w,
            c,
            contract(w, "ComparisonRouter", router).functions.order(key, False, 700_000_000, 120),
            manager,
        )
        hook = contract(w, "ServiceHook", a["hook"]).functions
        require(
            hook.observedTick().call() == 120 and not hook.qualification().call()[0], "afterSwap mismatch"
        )
        sendOperation(w, c, v.terminate(), t)
        sendOperation(w, c, v.exitLiquidity(), t)
        sendOperation(w, c, v.withdrawIdle(), t)
        require(v.positionLiquidity().call() == 0 and b.balanceOf(t).call() > 0, "principal recovery failed")
        print(
            f"{c['network']} pinned block {c['block']}: seed, external swap, hook observation and exit passed"
        )
