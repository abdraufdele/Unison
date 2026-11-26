# C1 service clock on the local v4 core

The hook measures qualifying seconds for the treasury's one accepted pool and live vault-owned position. Successful seed settlement starts the 300-second period. The opening band stays fixed. A qualifying position can remain unattended or trade outside the opening band while its own permitted range still covers that band. [C1 service terms](SERVICE-SPEC.md#service-clock-and-funded-payment)

## Observation and custody

Activation checks the deployed hook's runtime hash, bound vault, PoolManager, complete PoolId and unused add grant. After the seed debits, core liquidity, tick and price have been verified, the vault initializes the hook once. The hook installs the vault-confirmed ticks, salt and expected liquidity. It independently reads slot zero and core position liquidity using the fixed PoolId and the key derived from vault owner, ticks and salt. Full removal clears the hook's live ID. Reopening installs a fresh vault salt. Add admission still consumes a single grant for the exact positive leg. [Vault](../src/AgreementVault.sol) · [Hook](../src/ServiceHook.sol) · [Shared C1 range rules](../src/ServiceRange.sol)

| Boundary | Clock action |
| --- | --- |
| Third-party swap | Core invokes afterSwap. The hook authenticates core and the complete PoolKey, credits the stored old qualification, then observes the new core state. The sender and hook data supply no clock inputs. |
| Manager request | After authorization and execution checks, the vault calls beforeAdjustment once, before the first core leg. Successful final settlement installs the new identity and actual tick and liquidity. Both legs of a rerange share one timestamp and transaction. A failure reverts the pre-change checkpoint too. |
| Permissionless checkpoint | Folds the stored open interval into the total and returns cumulative Q. It takes no data, transfers no tokens and makes no core call. Repetition within one timestamp adds zero. |
| Termination or natural expiry | Stop uses stored qualification and the earlier of the execution time and original end. A projection already clips at exact expiry. A late checkpoint, swap, finalizer or liquidity exit can persist the final interval. Ended swaps remain available. |
| Terminal removal | Exit freezes the clock before a live removal, even before delayed expiry finalization. Successful settlement clears the live identity. Frozen Q and its service timestamp survive removal and withdrawal. |

The vault holds its existing custody lock across both hook calls and all core settlements. The unlock callback consumes its commitment before interacting, and the add callback consumes its separate one-use grant. The hook never reenters a vault write. Its only active-swap external reads are bounded core state reads. Permissionless checkpointing during settlement sees the previously installed position and the same timestamp. It cannot sample or install intermediate liquidity. Exit requires functioning vault, hook and core code, transferable principal tokens, chain inclusion and settlement. It uses neither the opening adapter nor the compensation escrow.

## Reads and events

- `qualifyingSeconds()` returns persisted Q. `projectedSeconds()` includes the open interval using the same arithmetic as persistence. The lower endpoint starts at successful activation and then advances with each checkpoint. The upper endpoint clips at scheduled end. An explicit stop credits the interval once and clears stored qualification.
- `qualification()` returns the effective boolean and a mask of failures. The bit values are 1 for unactivated, 2 for persisted stop, 4 for scheduled end reached, 8 for missing or mismatched live core liquidity, 16 for liquidity below the minimum, 32 for missing band coverage, 64 for an impermissible range, and 128 for the tick outside the half-open position range. Empty identity fails all position predicates. The pool and vault are fixed by construction and callback authentication.
- `storedQualified()` is the flag for the last installed interval. At exact expiry, effective qualification can already be false before a transaction persists the stop. The observed tick and liquidity describe the last service observation. Swaps after stop skip observation. Terminal removal clears observed liquidity.
- `ServiceCheckpoint` reports the service timestamp, cumulative seconds, old and new qualification, indexed position ID, observed tick and liquidity. Pair it with the vault's opening, position adjustment, period close and exit events to recover the identity and interval boundaries.

The clock follows the pre-change checkpoint and after-swap observation established by the bounded M1 experiment. The C1 implementation uses the product vault's acceptance, activation, management, salt retirement and terminal paths. Uniswap's pinned StateLibrary and TickMath carry MIT notices and Position carries BUSL-1.1. The existing core and Solmate checkout retains upstream notices. [M1 replay](../experiments/m1/WSL-RESULT.md) · [Attribution and license scope](../experiments/m1/README.md#attribution-and-license-scope)

## Local reconciliation

The independent accumulator reads the exact core position, pool tick, vault identity, band and lifecycle at the left endpoint of each interval. It applies the C1 predicates separately and sums the qualifying overlap before time advances. Each sequence compares this total with the hook projection, persisted checkpoints and final close. [Service clock tests](../test/integration/ServiceClock.t.sol)

| Fixture, in elapsed seconds | Qualifying intervals | Final Q |
| --- | --- | ---: |
| External interruption | [0, 90) at the seed position, then [210, 300) after the return swap. At 90 the outward swap reached the excluded upper tick 120. The return swap reached the tick-zero target price with stored tick −1. | 180 |
| Passive | [0, 300). One late close at 350 and a replay with repeated checkpoints gave the same total. | 300 |
| Early termination | [0, 120). This fixture spent 50 seconds funded before successful activation. Stop succeeded with core reads blocked. | 120 |
| Remove and reopen | [0, 100), [150, 180), [210, 300). Full removal retired salt 1. Salt 2 reopened at the same ticks. Removing one unit put L below the minimum until replenishment. | 220 |
| Extended range | [0, 60), [90, 120). At 30 an outward swap and rerange shared a timestamp. Tick 120 qualified in [−180, 180). Tick 180 failed. A return to stored tick −180 qualified. | 90 |

An unrelated position with the full 100,000,000,000 L in another real pool added zero during [40, 300) while the agreement was empty. Final Q stayed at 40.

The second rerange leg tested a one-unit B shortfall. The transaction rolled back the checkpoint to time 10,000 and persisted Q to zero, while its as-of-now projection remained 30. Position, balances, salt, consumed grants and cooldown reverted with it. A same-timestamp retry with the missing unit credited the original 30 seconds once. The custody-lock transfer probe also exercised a permissionless checkpoint during a live add. [Manager tests](../test/integration/ManagerOperations.t.sol)

The principal-recovery fixture blocked every adapter and escrow call and the escrow-to-treasury B transfer route. Treasury terminated at elapsed 10, removed real liquidity and withdrew principal and LP fees. Total treasury receipts including idle assets were 2,100,346,049 A and 1,900,054,977 B base units. Subsequent empty exits, withdrawals and termination left Q at 10. The exact-expiry fixture removed its live position before finalization with Q frozen at 300. The budget stayed separately held in M3. M4 added [earned reserves, claims, terminal refunds and the failure regression](COMPENSATION.md). [Lifecycle tests](../test/integration/AgreementLifecycle.t.sol)

## Size and replay

| Product | Runtime bytes | Creation bytecode bytes | Initcode with constructor arguments |
| --- | ---: | ---: | ---: |
| AgreementVault | 23,764 | 38,330 | 38,618 |
| ServiceHook | 4,738 | 5,155 | 5,283 |
| CompensationEscrow | 1,887 | 2,161 | 2,289 |
| OpeningQuote | 4,895 | 4,921 | 4,921 |

The compiled constructor ABIs use nine static words for the vault, four each for hook and escrow, and none for OpeningQuote. All four fit the 24,576-byte runtime and 49,152-byte initcode limits. The vault has 812 runtime bytes available. The root compiler profile and limits are unchanged.

From the [pinned native root setup](../README.md#setup), run

```bash
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --fuzz-seed 0x19112026 -vv
forge build --offline --use ~/.svm/0.8.26/solc-0.8.26 src/AgreementVault.sol --sizes
bash scripts/check_service_clock_mutation.sh
forge fmt --check src test
python3 scripts/check_opening_grid.py
(cd experiments/m1 && sha256sum -c SHA256SUMS)
```

The [mutation replay](../scripts/check_service_clock_mutation.sh) runs the baseline, copies the sources, verifies byte-identical tests, removes the vault's single pre-adjustment hook call and builds with the same compiler and settings. Each run uses a fresh ignored directory with private logs, its own source, artifacts and cache, and the existing pinned dependency checkout.

The complete root suite on native Forge 1.8.7 and Linux solc 0.8.26+8a97fa7a passed 100 tests across nine suites, with zero failed or skipped and exit 0. All 92 prior tests passed. Wrong-hash, opening-grid and service-clock fuzz tests each ran 256 inputs. The clock sequences exercised 24 actions per input (6,144 steps) with seed `0x19112026`, followed by early termination or delayed expiry and a frozen checkpoint. The separate three-test trace replay passed with exit 0. The product size build, format check, independent opening grid, shell syntax and all five M1 SHA-256 checks passed with exit 0. [Original manifest](../experiments/m1/SHA256SUMS)

The unchanged full-removal test passed on product source (exit 0). The isolated build succeeded (exit 0), with a mutability warning because the omitted call was the only write in the pre-adjustment function. The test reached full removal and failed with `OldIntervalLost(100, 0)` (exit 1). The arguments are the independently accumulated elapsed seconds and persisted Q. The original vault, hook and tests retained their source bytes. The replay's first compiler-message check expected a warning-free success banner and stopped before invoking the test. Accepting the compiler's success-with-warnings banner preserves the build exit check and the required exact assertion.

The corrected replay produced the same successful compilation and exact assertion failure in a fresh isolated copy. The baseline and mutation test files both had SHA-256 `3f81dd5ff246c703da482f69b4c5e9a1079b4f6001746827c8fcb1d92712f718`.
