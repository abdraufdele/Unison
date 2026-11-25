# C1 closeout review

Internal engineering review of one funded period on the pinned local core with exact-transfer mock tokens. This matrix ties terminal rights to the external calls that enforce them. The test names identify cases in the linked suites.

| Promise | Enforcement | Executed case and boundary |
| --- | --- | --- |
| Draft and Accepted cancellation | Vault `cancel` records cancellation without moving assets. The treasury can cancel before cutoff. Anyone can cancel from cutoff onward. `withdrawIdle` pays the fixed treasury. | `testTreasuryCancelsDraftWithGiftsAndOneAcceptance`, `testTreasuryCancelsAcceptedAndClosesAllConsentAndFunding`, and the exact-cutoff case cover zero funded rights and separately recoverable idle gifts. [Cancellation tests](../test/AgreementVaultCancellation.t.sol) |
| Funded cancellation | The original activation cutoff stays fixed. A cancelled vault cannot activate. The zero clock makes E zero and the credited F bounds the refund. | `testFundedCancellationIndependentPullsEventsAndRepeatRecovery` reconciles independent pulls, escrow gifts and repeat recovery. A blocked refund retains its credited right. [Cancellation tests](../test/AgreementVaultCancellation.t.sol) |
| Early termination and revocation | Treasury `terminate` closes once, freezes the recorded interval and records the stop. `add/remove/rerange` all require Active before mutation. | `testTerminationOrderedFirstRejectsOtherwiseExecutableOperations` and `testSameTimestampTerminationAfterAdjustmentAndIndependentExitOutsideEnvelope` cover both same-time orderings. An already included manager operation can precede revocation. [Manager tests](../test/ManagerOperations.t.sol) |
| Natural expiry and late finalization | `state` expires at scheduled end even with recordedStop zero. The clock clips there. `finalizeExpiry` can later persist the same end. | `testExactExpiryPreservesCorePositionAgainstManagerRemoval` checks an otherwise executable full removal against real core L. `testExactExpiryExitBeforeDelayedFinalization` closes after treasury has already exited. [Boundary tests](../test/CloseoutBoundary.t.sol) · [Lifecycle](../test/AgreementLifecycle.t.sol) |
| Frozen entitlement across close and removal | The hook credits stored qualification through the effective stop. Stopped checkpoints and swaps cannot extend Q. Terminal removal retires the identity and retains frozen seconds. | `testNoServiceBeforeActivationAndStopAt120` and `testPassiveProjectionPartitionAndLateExpiry` cover no prior credit, early and late stops, repeated checkpoints and ended swaps. D remains 300. [Clock tests](../test/ServiceClock.t.sol) |
| Treasury can remove LP and withdraw idle independently | Terminal `exitLiquidity` settles the current core position to the vault. `withdrawIdle` transfers the pair to treasury in kind. Either can run first. Neither pays escrow. | `testExpiredTreasuryReceivesPrincipalWithManagerRouteBlocked` exercises exact expiry before finalization. The generated corpus also varies the order of exit, idle withdrawal, payment and an ended swap. Pool inventory, fees and rounding determine actual receipts. [Boundary](../test/CloseoutBoundary.t.sol) · [Corpus](../test/CloseoutReconciliation.t.sol) |
| Claims, unpaid reserves and refunds | Escrow `claim` and `refund` share a lock. Both read the bound vault and its authenticated clock. Each eligible pull uses checkpointed Q. The refund requires a terminal state and deducts all earnings. | `testInterruptedServiceBothPullOrdersAndGiftsAtExactExpiry` and `testTerminalRefundLeavesUnpaidEarnedReserve` reconcile both terminal orders, a third-party caller, fixed recipients, gifts and the 20 B reserve. An activated vault rejects cancellation even after the original cutoff. [Settlement](../test/CompensationSettlement.t.sol) · [Lifecycle](../test/AgreementLifecycle.t.sol) |
| Failed and repeated pulls preserve rights | ExactToken checks the sender debit and recipient credit. A failed transaction reverts its counters and checkpoint. Zero-due eligible pulls transfer zero. | `testManagerPaymentFailureCloseoutWithFeeBearingPrincipal`, `testRefundFailurePreservesIndependentPrincipalAndManagerReceipt` and `testRemovalAndWithdrawalFailuresPreserveSeparateRetries` cover isolated payout routes, principal transfer failure, restoration and repetition. [Settlement](../test/CompensationSettlement.t.sol) · [Lifecycle](../test/AgreementLifecycle.t.sol) |

## State-changing entry points and callback review

- **Vault setup.** The constructor fixes the parties and cutoff. `revise` and `accept` require open terms. Revision clears prior consent. `fund` checks matching approvals, canonical escrow runtime and bindings, and exact deposits. `activate` rechecks funding, reference, PoolManager, pool and product hook, seeds under a fresh salt, and starts the clock only after settlement. `cancel` permanently rejects a successfully activated period. The opening adapter is read on preview/preflight and activation. [Vault](../src/AgreementVault.sol) · [Funding](../test/AgreementVaultFunding.t.sol)
- **Vault management.** Each manager entry checks caller, phase, chain, terms hash, expected ID, actual core liquidity, execution bounds and cooldown. The lock spans both rerange legs. The single-use unlock commitment includes operation, ticks, salt, signed L and limits. Only core can enter `unlockCallback` with the matching commitment. Its positive leg arms a separate hook grant. Both currency deltas settle between core and vault. A retired position cannot be reopened with its old salt. [Management evidence](MANAGER-OPERATIONS.md)
- **Hook.** Only the bound vault can call `armAdd`, `initializeClock`, `beforeAdjustment`, `installPosition` or `stopClock`. `beforeAddLiquidity` checks core, pool, owner and the exact add grant and consumes it. `afterSwap` authenticates core and pool and installs the new core observation after accruing the old one. Permissionless `checkpoint` credits the installed interval without sampling unsettled LP state. The callback tests cover wrong callers, replay and an attempted nested manager operation. [Hook](../src/ServiceHook.sol) · [Clock evidence](SERVICE-CLOCK.md)
- **Close and settlement.** Vault `terminate`, `finalizeExpiry`, `exitLiquidity` and `withdrawIdle` have separate authority and retry conditions. Escrow `credit` is bound to the funding vault. Permissionless `claim` and `refund` accept no beneficiary or entitlement inputs. A token callback during liquidity settlement can checkpoint and claim the previously delivered interval at the same timestamp. It cannot install intermediate L, unlock the vault again, or make the active budget refundable. Reentry into another escrow pull is locked. OpeningQuote only exposes reads. [Settlement evidence](COMPENSATION.md) · [Exact transfers and lock](../src/ExactToken.sol)

Core derives the LP owner from the caller on each liquidity modification. A direct call by another owner cannot select the vault as owner. Treasury and escrow recipients are constructor-bound, and manager bounds have no recipient field. A terminal refund can legitimately equal F when final E is zero. Any earned amount reduces the refund ceiling.

The treasury bears market and inventory risk. Principal exit requires functioning vault, hook and core contracts, transferable principal tokens, chain progress and transaction inclusion. A globally frozen B token could block B principal receipt as well as compensation. The failure fixtures block only the specified escrow-to-recipient route. Unsupported tokens, chain outages, external-market price accuracy and independent security assurance remain outside this review.

## Independent lifecycle reconciliation

Each sequence starts from the same real funded seed at timestamp 10,000. The model owns its clock, stop, salts, ranges, L, cooldown and transfer ledgers. It integrates the left-endpoint core tick and L for its expected identity through the earlier of the next action and the scheduled end. It computes `E = 100,000,000 × Q / 300` with integer floor. After each time advance and action it compares projected Q, E, successful claims/refunds, reserves, accounted custody and actual recipient balances to those expectations. At close it checks that accounted funding equals unpaid earnings plus the remaining refund. Escrow gifts have their own counter.

For each principal currency the model tracks gross input, removed principal, collected LP fees, vault gifts and withdrawals. It quotes a leg before mutation from the real square-root price and range with directional rounding, and computes native fees from the position's previous and current core fee growth. The shared fixture contains the same quote functions used by the prior manager tests. Each decision reconciles vault idle balances and treasury receipts, with treasury budget refunds accounted separately. [Stateful model](../test/CloseoutReconciliation.t.sol) · [Principal and fee calculations](../test/fixtures/PositionAccountingFixture.sol)

The corpus uses 32 deterministic seeds, `keccak256(abi.encode(uint256(0x19112026), uint256(i)))` for indices 0–31. Even indices terminate early, odd indices reach exact expiry and finalize late. Each of three active rounds shuffles a trader swap, a manager adjustment, a checkpoint, a claim, gifts and invalid calls. Timing, swap distance and gift size vary by seed. Each terminal sequence shuffles a claim, a refund, an idle withdrawal, a live exit, a swap and a checkpoint. That gives 768 shuffled action slots, plus the time advances, injected failures, retries and repeated closes. Four test transactions each run eight seeds. An initial single-transaction run exhausted the existing test gas limit.

Every sequence checks a failed second rerange leg before retry, including balances, fee snapshot, actual position, cooldown, old clock checkpoint, empty proposed position, unused add grant and unusable unlock data. It also blocks and retries a positive manager payment and a positive treasury refund independently. Over the corpus the scheduled actions include 96 active swaps, 32 each of partial removal, addition and successful rerange, 32 failed second legs, 96 active checkpoints, 96 pairs of escrow/vault gifts and 32 ended swaps. Terminal success is verified from actual receipts.

| Seed indices | Positive manager claims | Positive principal withdrawals | Positive terminal refunds | Live LP exits |
| --- | ---: | ---: | ---: | ---: |
| 0–7 | 28 | 14 | 8 | 8 |
| 8–15 | 27 | 13 | 8 | 8 |
| 16–23 | 28 | 13 | 8 | 8 |
| 24–31 | 27 | 12 | 8 | 8 |
| **All 32** | **110** | **52** | **32** | **32** |

Counts for claims and withdrawals include only pulls with positive proceeds. Each sequence asserts a positive refund and one live exit. The three existing fuzz tests each ran 256 inputs separately from this fixed corpus.

## Mutation evidence

Both baseline tests passed with exit 0 before the isolated challenges. Each copy retained the original tests, changed one vault expression or call, compiled successfully with native solc (exit 0), and ran its focused test with a full trace. [Replay script](../scripts/check_closeout_mutation.sh)

| Isolated change | Behavior actually reached | Native result |
| --- | --- | --- |
| In the vault's effective expiry comparison, replace ≥ with >. | At exactly scheduled end, before finalization, the named manager's valid full-removal request passed the phase check. The real core settled the removal. The vault emitted PositionAdjusted for salt 1 with L zero. The test then read actual core L for that key. | Exit 1 at `ExpiredPositionChanged(100000000000, 0)`. |
| In live terminal `exitLiquidity`, insert a mandatory escrow `claim()` immediately before stopping the clock. | The exit trace entered the claim and attempted the escrow-to-manager B transfer. That specific route reverted. The later withdrawal could deliver only idle B. The independently checked treasury balance lacked all 498,228,754 B units of removal proceeds. | Exit 1 at `PrincipalReceiptShort(1900054977, 1401826223)`. |

The [old-interval challenge](SERVICE-CLOCK.md) and [unpaid-reserve challenge](COMPENSATION.md) remain applicable. M5 changed neither their product paths nor their test/replay inputs, so their previous executed results are retained. Private traces and copies from the two new mutations are ignored.

The review demonstrated no defect in the supported product paths. M5 and A4 passed for local C1. The specified A5 challenges now have targeted failures and independent time/asset reconciliation. This is bounded internal evidence. The M4 ABI stayed stable enough for read-only contract views. The next engineering dependency is M6's matched comparison and cost measurement. A1 and preliminary A2/A3 still need customer and economic evidence, and A6 requires the reproducible demo.

## Reproduction and size

Use the [pinned native setup](../README.md#setup). The full root suite with Forge 1.8.7 and Linux solc 0.8.26+8a97fa7a passed 115 tests across 12 suites, zero failed or skipped, exit 0. Focused traces passed both boundary cases and the first eight-seed shard, exit 0.

```bash
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --fuzz-seed 0x19112026 -vv
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --match-path test/CloseoutBoundary.t.sol -vvvv
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --match-test testCloseoutSeeds00To07 -vvvv
bash scripts/check_closeout_mutation.sh revocation
bash scripts/check_closeout_mutation.sh payment
forge build --offline --use ~/.svm/0.8.26/solc-0.8.26 src/AgreementVault.sol --sizes
forge fmt --check src test
(cd experiments/m1 && sha256sum -c SHA256SUMS)
```

| Product | Runtime bytes | Creation bytes | Initcode with constructor arguments |
| --- | ---: | ---: | ---: |
| AgreementVault | 23,891 | 39,556 | 39,844 |
| CompensationEscrow | 2,986 | 3,260 | 3,388 |
| ServiceHook | 4,738 | 5,155 | 5,283 |
| OpeningQuote | 4,895 | 4,921 | 4,921 |

The vault, escrow, hook and helper take nine, four, four and zero static ABI words respectively. The vault retains 685 runtime bytes. All five [M1 SHA-256 digests](../experiments/m1/SHA256SUMS) matched. The quote fixture uses the pinned core's StateLibrary, SqrtPriceMath, TickMath and FullMath with their existing licenses. [Attribution](../experiments/m1/README.md#attribution-and-license-scope)
