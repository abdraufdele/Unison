# What did position-linked settlement buy in C1?

The two managed arrangements delivered identical liquidity, fills, fees and principal in all seven local scenarios. Unison made the payment for qualifying seconds enforceable onchain. Both arrangements already supported independent principal exit and protected earned pay. In the interrupted period, Unison cost an additional **9,405,354 gas** across treasury, manager and traders. The 40 B refund transferred value between the parties. A buyer-specific economic advantage remains unproven.

## Matched experiment

All arms started with the same six-decimal tokens, 2,000 A and 2,000 B of inventory, a separate available 100 B, parity opening, 300 seconds, 0.30% fixed fee, spacing 60, zero protocol fee and one LP. The seed held 100 billion raw L at [−120, 120), costing 598.173777 of each token. One locally deployed pinned v4 PoolManager executed every order and position change. Snapshots isolated each arm and scenario. The router submitted the same exact-input offers, directions, times and limiting prices within each case.

| Arm | Implementation and cost-relevant differences |
| --- | --- |
| A · Passive | Comparison-only fixed-pool position owner. Treasury approved both tokens, paid only the seed amounts and kept its idle inventory and 100 B liquid. An owner removal also delivered fees and principal directly to its wallet. No manager, mandate or escrow. |
| B · Retainer | Comparison-only bounded mandate with constructor-created elapsed-time escrow, fixed recipients, two consents, exact prefunding, independent exit, earned reserves and terminal pull refund. Code fixes the terms and parity opening. It implements the symmetric reranges used here, with C1's identity, cooldown, window, execution ticks, range, L, gross input and minimum principal output bounds. It has a smaller action surface, a simpler commitment and no external opening read, service checkpoint or callback on swaps. It is a benchmark harness. |
| C · Unison | Actual AgreementVault including its constructor-created OpeningQuote, ServiceHook deployed with the required CREATE2 bits, CompensationEscrow and the existing mock opening adapter. Predicted addresses allowed final wiring at construction. Dedicated deployment includes the hook installer and publishing the observation. The product also supports revision, opening/reference validation, wider management capabilities and stronger settlement checks. The whole mandate cost difference includes those differences. |
| D · Observer | **Modeled, unmeasured.** Apply B's management and independent exit, reconstruct C1 entitlement from complete ordered core/position records, submit cumulative signed statements to programmable escrow, reserve disputed rights and adjudicate challenges. With accurate timely certification its computed earnings would equal C's for every row below. Intermediate claims need certified cumulative rights. Missing data, reporter failure or a dispute can delay settlement. Reporting gas, staffing, dispute frequency, resolution time and end-to-end guarantees were not measured. |

The two managed arms requested the same numerical bounds and actions under their own terms hash and live position ID. At second 120 the recovery requests used a same-second window, execution ticks [−240, 240), 2,000 gross inputs per token and zero minimum outputs. Neither arm could spend the escrow for a rerange. All setup and measurement code lives outside product source. [Comparison contracts](../experiments/m6/Comparison.sol) · [Worksheet](C1-COMPARISON.md)

## Service, execution and settlement

Q integrates elapsed time using core liquidity for the expected owner, ticks and salt, the permitted range covering the opening band and the half-open in-range tick. All qualifying intervals delivered 100 billion L, so delivered qualifying L-seconds equal Q times 100 billion. Every scenario ended with actual treasury receipt and zero outstanding reserve. A paid zero and kept its 100 B in every row.

| Scenario | Q seconds, A / B / C | Final B paid, retainer / Unison | Unison refund B | What the observed path supports |
| --- | --- | --- | ---: | --- |
| Flat | 300 / 300 / 300 | 100 / 100 | 0 | Unattended seed delivered full service. Passive sufficed. |
| Interrupted | 180 / 180 / 180 | 100 / 60 | 40 | Identical service interruption. C settled the missing 120 seconds directly. Passive delivered the same liquidity. A retainer suits availability pay. |
| Feasible recovery | 90 / 270 / 270 | 100 / 90 | 10 | Both managers reranged to [−180, 180) at seed L. The follow-on 50 B offer bought 49.231009 A in both, ending at tick 129. Passive consumed zero and reached its limit at tick 230 with zero active L. Management restored 180 seconds and a fill. B already delivered both. |
| Infeasible recovery | 90 / 90 / 90 | 100 / 30 | 70 | Both requests for [−240, 240) at 200 billion L reverted at the gross principal bound. The old position and idle balances persisted. Passive avoided the failed operation. |
| Delayed return | 150 / 150 / 150 | 100 / 50 | 50 | Delivering the return order at 240 instead of 210 cost all three 30 qualifying seconds. Only the position-linked invoice changed with the delay. |
| Early close, blocked payment | 180 / 180 / 180 | 60 / 60 | 40 | Both paid 40 B at 120, failed a recipient-specific claim at 179, stopped at 180 and delivered principal while payment remained blocked. Both refunded 40 B and later paid the original 20 B reserve. B already supplied these protections. |
| External drift and repeated swaps | 300 / 300 / 300 | 100 / 100 | 0 | Two further 0.25 B orders left the seed qualifying. A synthetic external mark rose to 1.10 B/A at 150. The later A sale executed 936.1909 bp below that reference including fees, even as full service was paid. Passive sufficed for the fixed-band job. A buyer seeking fair-market execution needs a different metric. |

Outward offers at second 90 were 1 B in flat, early and drift, and 700 B elsewhere, limited at tick 120. Flat and drift returned 1 A at 210. Interrupted and delayed returned 700 A at 210 and 240 respectively. All returns were limited at tick 0. The feasible follow-on at 150 had an upper limit of 230. Drift repeats at 110 and 115 had an upper limit of 120. Interrupted added a 1 A post-expiry offer at 301, limited at −120, before removal. The 700 B outward consumed 603.584180 B and returned 598.173776 A. The 700 A return consumed 599.973699 A and returned 601.773426 B. Each unconsumed balance stayed with the trader. All 45 order transactions succeeded, including passive's zero fill. [Per-order intentions, fills, unspent input, fees, slippage and ending state](../experiments/m6/results/orders.csv)

The common external mark is 1 B/A, except from second 150 in the drift case. Marking changes valuation only. Signed slippage in basis points is 10,000 times one minus actual output divided by marked output for the **consumed** input. A negative value means a better execution than the mark. A zero fill has no execution price. The mark is synthetic, with no external oracle or arbitrage flow.

| Inventory after receipt, whole tokens | A | B | LP fees A / B included | Marked inventory B |
| --- | ---: | ---: | --- | ---: |
| Flat, all | 2,000.002998 | 2,000.002998 | 0.002999 / 0.002999 | 4,000.005996 |
| Interrupted, all | 2,002.799920 | 2,000.813760 | 1.802921 / 1.810752 | 4,003.613680 |
| Feasible, passive | 1,401.826223 | 2,603.584177 | 0 / 1.810752 | 4,005.410400 |
| Feasible, managed | 1,352.595213 | 2,653.584175 | 0 / 1.960751 | 4,006.179388 |
| Infeasible, all | 1,401.826223 | 2,603.584177 | 0 / 1.810752 | 4,005.410400 |
| Delayed, all | 2,001.799920 | 2,001.810751 | 1.799921 / 1.810752 | 4,003.610671 |
| Early, all | 1,999.003008 | 2,000.999998 | 0 / 0.002999 | 4,000.003006 |
| Drift, all | 1,999.504520 | 2,000.502978 | 0.002999 / 0.004499 | 4,199.957950 |

The detailed ledger separates idle holdings immediately before exit, principal released by the burn, lifetime LP fees, final treasury quantities including unused/refunded budget, compensation and both marked values. Fees collected during a successful rerange already enter idle custody. At exit the runner independently quotes principal from core price and ticks, reads fee growth, checks actual wallet receipts and conserves each currency including rounding dust. Post-exit pool and owned L are zero. The ending tick and square-root price refer to the last order, including the post-expiry order where present. [21 reconciled ledgers, base units](../experiments/m6/results/outcomes.csv)

## Cost by payer and economic hurdle

Each measured write is a separate locally mined Cancun transaction. Gas is receipt `gasUsed`, including intrinsic/calldata cost, execution, creation and applicable refunds. Access warmth resets per transaction. Nested calls share warmth. No access lists, gas estimates, batched setup, execution-only call samples, mainnet prices or L2 data fees enter the totals. Both managed deployments include their nested creations once. Natural expiry permitted exit without a finalizer transaction. Positive claims and refunds were pulled, and the early failed claim and failed reranges incurred actual receipt gas. [Gas by payer, operation, timestamp and status](../experiments/m6/results/gas.csv)

| Scenario | Dedicated gas A / B / C, millions | C−B gas by treasury / manager / trader | Joint gas hurdle vs B / vs A at 10 gwei, ETH |
| --- | --- | --- | --- |
| Flat | 1.821 / 3.525 / 12.805 | 9,104,545 / 70,909 / 104,426 | 0.092799 / 0.109839 |
| Interrupted | 1.993 / 3.697 / 13.103 | 9,190,339 / 70,909 / 144,106 | 0.094054 / 0.111094 |
| Feasible | 1.736 / 3.861 / 13.373 | 9,204,512 / 200,324 / 107,250 | 0.095121 / 0.116368 |
| Infeasible | 1.679 / 3.754 / 13.195 | 9,202,453 / 175,684 / 62,187 | 0.094403 / 0.115158 |
| Delayed | 1.878 / 3.582 / 12.961 | 9,204,512 / 70,909 / 104,232 | 0.093797 / 0.110837 |
| Early | 1.676 / 3.644 / 12.996 | 9,154,030 / 138,862 / 59,363 | 0.093523 / 0.113202 |
| Drift / repeats | 2.053 / 3.757 / 13.119 | 9,104,545 / 70,909 / 186,152 | 0.093616 / 0.110657 |

One dedicated setup per period used **1,373,997 / 2,876,949 / 11,964,579** gas for A/B/C. In C the vault creation, including OpeningQuote, cost 6,674,939. The hook deployment cost 1,073,500, the dedicated installer 1,229,820, escrow 793,026 and mock adapter 212,312. Offchain salt search used no transaction. Shared infrastructure is itemized separately. To price a fresh pool stack add 4,982,358 gas to treasury for PoolManager and the router/lens, and 88,200 to the trader for two approvals, equally in each arm. The synthetic tokens and mints used another 953,396 fixture gas. The early failure injection/restoration cost 96,512 fixture gas per managed arm. A reused router/core or installer changes allocations. The one-period product vault and escrow remain dedicated. Future adapter sourcing and its update costs are unknown.

| Matched trader receipt | No hook | Unison | Difference |
| --- | ---: | ---: | ---: |
| Interrupted outward | 157,347 | 219,534 | 62,187 |
| Interrupted return | 160,685 | 202,730 | 42,045 |
| Drift repeated, each of two | 114,838 | 157,101 | 42,263 |
| Interrupted post-close | 115,505 | 155,379 | 39,874 |

For these pairs the trade intentions, pre-swap core price/L, wallet flows and resulting state match. The hooked pool has a different pool ID, nonzero hook-address calldata and hook storage/callback work. The figures price the whole path. The post-close hook remained attached. The two repeats are distinct cold-start transactions with unchanged qualification and slightly different prices. These samples do not define an average for other traffic.

**Break-even.** Multiply gas by gwei per gas and divide by one billion for ETH. At 5 / 10 / 30 gwei the interrupted joint premium over B is **0.04702677 / 0.09405354 / 0.28216062 ETH**. Its trader component is **0.00072053 / 0.00144106 / 0.00432318 ETH**. For each row the buyer needs enough verified service value, reconciliation work avoided or dispute loss avoided to cover its own premium, at least the treasury column times its gas price before other costs or transfers. The joint decision adds manager and trader incidence and incremental review, monitoring, capital and operating costs. Record a refund as a buyer cash-flow benefit at an agreed B/ETH mark and as foregone manager pay. It creates no joint saving. Feasible recovery improved delivery over A, but B bought the same recovery for 0.02124724 ETH of extra gas over A at 10 gwei, before compensation and unmeasured costs. The C−B premium in that row must be justified by settlement itself.

Treasury funded both managed arms ten seconds before activation. In the interrupted case B kept 100 B until the final claim at 306, or 8.7778 B-hours. C returned 40 B at 304 and paid 60 B at 306, or 8.7556 B-hours. Both early-close arms consumed 4.6889 B-hours. A kept the entire budget and its idle pair balances liquid. Managed pair inventory was funded at −10 and received at end+3, with composition changing as orders executed. An opportunity rate and agreed asset marks are needed to price this time. Operator/retry labor, review, monitoring, external liquidity effects, capital rates and customer willingness to pay are unmeasured.

Where the buyer accepts certified delayed settlement, D could deliver the same payment schedule conditional on evidence and interim certification. Compare its reporting, verification, dispute and delay costs against C's direct settlement and continuing swap costs. B's receipts provide a no-hook management reference. D's contract deployment, submissions, security guarantees and total costs are unmeasured. Passive is sufficient on flat paths; the retainer is cheaper for availability and for the observed recovery and early close. A1, A2 and A3 remain open pending evidence from both roles about the same deal and the cost of an actual reconciliation problem.

## Replay and verification

Use the [pinned local setup](../README.md#setup). Executed with Forge and Anvil 1.8.7, native solc 0.8.26+8a97fa7a, Cancun, via IR, optimizer 200, Python 3.12.3 and existing Web3.py 7.13.0 (eth-abi 5.2.0, eth-utils 5.3.1). The runner checks compiled source hashes and settings. It creates its own private IPC endpoint and fresh genesis, uses fixed chain timestamps and terminates its loopback-only process on exit. From the repository root, the first command is needed only for missing or changed artifacts.

```bash
timeout 180s forge build --offline --use ~/.svm/0.8.26/solc-0.8.26 experiments/m6/Comparison.sol test/fixtures/CustodyFixture.sol test/fixtures/MockOpeningReferenceAdapter.sol experiments/m1/vendor/v4-core/src/PoolManager.sol
m6_output=$(mktemp -d)
timeout -k 5s 240s python3 -B experiments/m6/run.py "$m6_output"
python3 -B experiments/m6/check.py "$m6_output"
diff -ru experiments/m6/results "$m6_output"
```

The offline checker also reads the published tables directly with `python3 -B experiments/m6/check.py`. It reconstructs service intervals and entitlement, compares order schedules, checks failures, fees, reserves, marked balances and prints transaction counts and exact spend per payer. The prior 115-test product run remains applicable to the unchanged product, fixtures and configuration. Local mocks and comparison code retain their own notices. Core and Solmate retain their upstream file-specific licenses. [Runner](../experiments/m6/run.py) · [Offline checks](../experiments/m6/check.py) · [Upstream pins and licenses](../experiments/m1/README.md#attribution-and-license-scope)
