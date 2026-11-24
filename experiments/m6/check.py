"""Reconcile the public M6 tables offline. Print payer gas and break-even inputs."""
import csv
import sys
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

UNIT = 10**6
MIN_L = 10**11
CASES = ("flat", "interrupted", "feasible", "infeasible", "delayed", "early", "drift")
PAYERS = ("treasury", "manager", "trader")


def rows(directory, name):
    with (directory / (name + ".csv")).open() as f:
        return list(csv.DictReader(f))


def select(table, arm, case):
    return [r for r in table if r["arm"] == arm and r["scenario"] == case]


def check_case(case, outcome, orders, transactions):
    arm = outcome["arm"]
    close = 180 if case == "early" else 300
    actions = [(int(r["second"]), "order", r) for r in orders]
    changes = [r for r in transactions if r["operation"] == "rerange"]
    actions.extend((int(r["second"]), "rerange", r) for r in changes)
    assert len(changes) == int(arm != "A" and case in ("feasible", "infeasible"))
    failed = {r["operation"] for r in transactions if r["status"] == "0"}
    assert failed == ({"rerange"} if case == "infeasible" and arm != "A" else
                      {"failed claim"} if case == "early" and arm != "A" else set())
    actions.append((close, "close", {}))
    tick, edge, last, qualified = 0, 120, 0, 0
    fees, offered = Counter(), Counter()
    for t, kind, r in sorted(actions, key=lambda event: event[0]):
        if - edge <= tick < edge:
            qualified += min(t, close) - min(last, close)
        last = t
        if kind == "order":
            offer, used, unspent = (int(r[k]) for k in ("offer", "used", "unspent"))
            assert used + unspent == offer and 0 <= used <= offer
            assert (int(r["output"]) > 0) == (used > 0)
            assert int(r["input_fee"]) <= used
            tick = int(r["tick"])
            fees[r["input"]] += int(r["input_fee"])
            offered[r["input"]] += 1
            assert int(r["pool_L"]) == (MIN_L if - edge <= tick < edge else 0)
        elif kind == "rerange" and r["status"] == "1":
            edge = int(outcome["edge"])
    assert (tick, qualified) == (int(outcome["end_tick"]), int(outcome["Q"]))
    assert int(outcome["qualified_L_seconds"]) == MIN_L * qualified
    assert int(outcome["owned_L"]) == MIN_L
    total = 100 * UNIT
    earned = {"A": 0, "B": total * close // 300, "C": total * qualified // 300}[arm]
    refund = 0 if arm == "A" else total - earned
    assert int(outcome["paid_at_close"]) + int(outcome["reserve_at_close"]) == earned
    assert (int(outcome["final_paid"]), int(outcome["refunded"]), int(outcome["final_reserve"])) == (earned, refund, 0)
    for token in "AB":
        lp_fee = int(outcome["fees_" + token])
        assert 0 <= fees[token] - lp_fee <= offered[token]  # Fee growth and collection round down.
        inventory = int(outcome["inventory_" + token])
        # A successful rerange has already swept some LP fees into idle custody.
        remaining_fee = inventory - int(outcome["idle_" + token]) - int(outcome["burn_" + token])
        assert 0 <= remaining_fee <= lp_fee
        if not any(r["status"] == "1" for r in changes):
            assert remaining_fee == lp_fee
        kept_budget = (total if arm == "A" else refund) if token == "B" else 0
        assert int(outcome["treasury_" + token]) == inventory + kept_budget
    mark = Decimal(outcome["mark_B_per_A"])
    for field in ("inventory", "treasury"):
        value = mark * int(outcome[field + "_A"]) + int(outcome[field + "_B"])
        assert value / UNIT == Decimal(outcome[field + "_value_B"])
    swap_receipts = [r for r in transactions if r["payer"] == "trader"]
    assert [r["second"] for r in swap_receipts] == [r["second"] for r in orders]


def main(directory):
    results, orders, gas = (rows(directory, name) for name in ("outcomes", "orders", "gas"))
    assert len(results) == 3 * len(CASES)
    costs = defaultdict(Counter)
    print("case arm transactions treasury_gas manager_gas trader_gas")
    for case in CASES:
        intents = []
        for arm in "ABC":
            outcome, = select(results, arm, case)
            trades = select(orders, arm, case)
            lifecycle = select(gas, arm, case)
            check_case(case, outcome, trades, lifecycle)
            intents.append([tuple(r[k] for k in ("second", "input", "offer", "limit_tick")) for r in trades])
            workload = [r for r in select(gas, arm, "setup") + lifecycle if r["payer"] in PAYERS]
            spend = costs[case, arm]
            for r in workload:
                spend[r["payer"]] += int(r["gas"])
            print(case, arm, len(workload), *(spend[p] for p in PAYERS))
        assert intents[0] == intents[1] == intents[2]
        print("C minus B and A, gas", *(costs[case, "C"].total() - costs[case, other].total() for other in "BA"))
    print(f"Verified {len(results)} lifecycles, {len(orders)} orders and {len(gas)} receipt rows including setup.")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).with_name("results"))
