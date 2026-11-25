"""Independent core, custody and cooldown checks on the blocks actually mined by Chromium."""
from collections import Counter

from web3 import Web3
from web3.logs import DISCARD

from artifacts import fixture


def reconcile_manager(run, session):
    eth, vault = run.w.eth, run.v
    receipts = {r["action"]: eth.get_transaction_receipt(r["hash"]) for r in session.history}
    adjustment = receipts["rerange"]
    n = adjustment.blockNumber
    swap_block = receipts["rangeSwap"].blockNumber
    exit_receipt = receipts["rangeExit"]
    final = receipts["rangeWithdraw"].blockNumber
    unit, liquidity = fixture.UNIT, fixture.L

    def pair(address, block):
        return [token.functions.balanceOf(address).call(block_identifier=block) for token in (run.a, run.b)]

    def position(edge, salt, block):
        return run.router.functions.position(run.key, vault.address, -edge, edge, fixture.word(salt)).call(block_identifier=block)

    # Account for every core position mutation in this pool from the funded anchor.
    pool_id = vault.functions.positionPoolId().call()
    changes = run.core.events.ModifyLiquidity().get_logs(from_block=int(session.manifest["anchor"]["number"]),
                                                         to_block=final, argument_filters={"id": pool_id})
    assert len(changes) == 4
    book = Counter()
    for entry in changes:
        x = entry.args
        assert x.sender == vault.address
        key = (x.tickLower, x.tickUpper, int.from_bytes(x.salt, "big"))
        assert key in ((-120, 120, 1), (-180, 180, 2))
        book[key] += x.liquidityDelta
        assert book[key] >= 0 and sum(v > 0 for v in book.values()) <= 1
    assert all(v == 0 for v in book.values())
    assert [position(120, 1, n-1)[3], position(180, 2, n-1)[3]] == [liquidity, 0]
    assert [position(120, 1, n)[3], position(180, 2, n)[3]] == [0, liquidity]

    def identity(edge, salt):
        return Web3.keccak(run.w.codec.encode(["bytes32", "address", "int24", "int24", "bytes32"],
                           [pool_id, vault.address, -edge, edge, fixture.word(salt)]))
    old, new = identity(120, 1), identity(180, 2)
    tx = eth.get_transaction(adjustment.transactionHash)
    fn, args = vault.decode_function_input(tx.input)
    assert fn.fn_name == "rerange" and tx["from"] == run.actors["manager"] and tx.to == vault.address
    assert args["expectedId"] == old and (args["lower"], args["upper"], args["liquidity"]) == (-180, 180, liquidity)
    assert args["bounds"] == dict(termsHash=run.h, validFrom=2030, deadline=2040, tickLower=0, tickUpper=1,
                                  maxInput0=900*unit, maxInput1=900*unit, minOutput0=598*unit, minOutput1=598*unit)
    assert vault.functions.positionId().call(block_identifier=n-1) == old
    assert vault.functions.positionId().call(block_identifier=n) == new
    assert vault.functions.lastAdjustment().call(block_identifier=n-1) == 0
    assert vault.functions.lastAdjustment().call(block_identifier=n) == 2031
    # Read-only probe immediately after the successful operation; valid caller, ID, ticks, period and limits.
    def removal_args(at):
        return [new, liquidity//4, (run.h, at, at, -180, 180, 900*unit, 900*unit, 0, 0)]
    probe = {"from": tx["from"], "to": tx.to, "data": vault.encode_abi("remove", args=removal_args(2031))}
    error = run.w.provider.make_request("eth_call", [probe, hex(n)])["error"]
    assert error["data"] == Web3.to_hex(Web3.keccak(text="AdjustmentCooldown()")[:4])
    vault.functions.remove(*removal_args(2090)).call({"from": tx["from"]}, block_identifier=swap_block)

    q96 = 1 << 96
    def principal(edge, sqrt, adding):
        lo, hi = [run.router.functions.price(tick).call() for tick in (-edge, edge)]
        assert lo <= sqrt <= hi
        fractions = [(liquidity*(hi-sqrt)*q96, hi*sqrt), (liquidity*(sqrt-lo), q96)]
        return [(num + (den-1 if adding else 0))//den for num, den in fractions]

    recovered, installed = principal(120, q96, False), principal(180, q96, True)
    remove_leg, add_leg = vault.events.PositionAdjusted().process_receipt(adjustment, errors=DISCARD)
    # Compare both v4 signed int128 words independently with rounded principal at the observed price.
    def packed(pair):
        return (pair[0] << 128) + (pair[1] % (1 << 128))
    assert remove_leg.args.principal == packed(recovered) and remove_leg.args.fees == 0
    assert add_leg.args.principal == packed([-a for a in installed]) and add_leg.args.fees == 0
    before, after = pair(vault.address, n-1), pair(vault.address, n)
    assert after == [idle+out-paid for idle,out,paid in zip(before, recovered, installed)]
    assert all(x >= 598*unit for x in recovered) and all(x <= 900*unit for x in installed)
    assert position(120, 1, n-1)[4:6] == [0, 0]
    assert [run.hook.functions.qualifyingSeconds().call(block_identifier=i) for i in (n-1,n)] == [30,31]

    before_trade, after_trade = pair(run.trader, swap_block-1), pair(run.trader, swap_block)
    out, used = after_trade[0]-before_trade[0], before_trade[1]-after_trade[1]
    swap, = run.core.events.Swap().process_receipt(receipts["rangeSwap"], errors=DISCARD)
    sqrt, tick, _, owned, fee_a, fee_b, *_ = position(180, 2, swap_block)
    assert (swap.args.id,swap.args.sender,swap.args.amount0,swap.args.amount1,swap.args.tick) == (
        pool_id,run.router.address,out,-used,tick)
    assert 0 < used <= 700*unit and out > 0 and owned == liquidity and tick == 120
    assert (vault.functions.bandLower().call(),vault.functions.bandUpper().call()) == (-120,120)
    assert run.hook.functions.qualification().call(block_identifier=swap_block) == [True,0]
    assert fee_b > 0 and fee_a == 0
    exit_event, = vault.events.LiquidityExited().process_receipt(exit_receipt, errors=DISCARD)
    x = exit_event.args
    assert [x.principal0,x.principal1] == principal(180,sqrt,False)
    assert [x.fees0,x.fees1] == [fee_a, fee_b]
    received = [after[0]+x.principal0+fee_a, after[1]+x.principal1+fee_b]
    assert pair(vault.address,final-1) == received
    assert [a-b for a,b in zip(pair(run.owner,final),pair(run.owner,final-1))] == received
    assert pair(vault.address,final) == [0,0]
    assert all(pair(run.esc.address,i) == [0,100*unit] for i in range(n-1, final+1))
    print("Run",session.manifest["runId"],"vault",vault.address,"core",run.core.address,"manager",tx["from"])
    print("Terms",Web3.to_hex(run.h),"pool",Web3.to_hex(pool_id),"old",Web3.to_hex(old),"new",Web3.to_hex(new))
    print("Raw A/B: idle before",before,"removed",recovered,"added",installed,"idle after",after)
    print("Order: B used",used,"unspent",700*unit-used,"A received",out,"actual tick",tick)
    print("Exit: principal",[x.principal0,x.principal1],"fees",[fee_a,fee_b],"treasury",received)
