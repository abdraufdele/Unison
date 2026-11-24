# Bounded C1 management on the local core

The named manager can call `add`, `remove` and `rerange` while the vault is Active. Supply the current terms hash, expected position ID, inclusive validity timestamps, a lower-inclusive and upper-exclusive tick interval, maximum inputs on an add leg and minimum principal outputs on a remove leg. The vault applies the C1 range, amount, tick, window and cooldown rules to the whole request. A manager may leave one unit of liquidity, below the 100,000,000,000 service minimum, or remove everything. Service-time accounting is pending. [C1 terms](SERVICE-SPEC.md#manager-permissions-and-position-identity)

## Position, custody and callbacks

`positionId()` returns zero when empty. A live ID is the Keccak-256 of the ABI encoding of the configured PoolId, vault address, position ticks and salt. The accepted terms also bind the chain and PoolManager. The band stays fixed while the position ticks can change. Full removal clears live liquidity and retires the salt. Each opening increments the salt, including a return to the original ticks.

Rerange settles the removal into the vault and then opens the new range using vault inventory, all under one transaction lock. Each leg gets a separate core unlock. Its single-use commitment covers the operation kind, both ticks, salt, signed liquidity delta and both applicable token limits. The hook separately consumes an add grant bound to the kind and exact positive leg after checking core, PoolId and vault sender. The vault checks principal from the signed net core delta minus LP fees before settling either currency. The vault pays core or takes proceeds to itself and verifies the actual core liquidity after each leg. The escrow has no role in those calls. [Vault](../src/AgreementVault.sol) · [Hook](../src/ServiceHook.sol)

The old position is available in `_beforeAdjustment` after identity, actual liquidity and execution checks. M3 can checkpoint it there. The final core-confirmed position is available in `_afterAdjustment`, where the vault records one successful adjustment time. Both legs revert together on failure. M3 still needs to initialize the clock on activation, observe external swaps, and clip accrual at termination and expiry.

## Real-core evidence

| Case | Observed result |
| --- | --- |
| Identity and liquidity | An in-place add reached 200,000,000,000 L under salt 1. Partial removal left 1 L. Full removal produced empty ID zero. Reopening the same ticks used salt 2, and the stale ID failed. Core confirmed the retired position held zero. |
| Range and execution | The tests cross the actual tick envelope [−240, 240), check caller subintervals, hit both 30-second timing boundaries, and reject a 31-second window. An opening band 300 ticks wide isolates the 480-tick width cap from the per-edge extension cap. |
| Gross inputs and fees | For each currency, a real swap accrued fees on the managed position. A gross input of 2,000,000,001 failed with available inventory and a net debit below the C1 cap. A caller maximum one unit below 2,000,000,000 also failed. The exact cap succeeded. Output minima one unit above removal principal failed even with fees available. Vault receipts and core debits reconciled to principal plus fees. |
| Second-leg inventory failure | At parity, removing the seed left 1,999,999,999 B available. The new [−240, 120) position needed exactly 2,000,000,000 B. The B debit failed after the A payment. Both core and vault balances, old core liquidity, live ID, salt and cooldown returned to their pre-call values. The proposed position held zero and the callback grants were unusable. A one-unit B gift allowed the same request to succeed at the same timestamp under salt 2. Escrow retained all 100,000,000 B. |
| Revocation and exit | Management succeeded before termination at the same timestamp. All three operations failed when ordered after termination or at exact expiry before finalization. After a rerange and a third-party swap to tick 300, treasury exited during cooldown with adapter and escrow reads blocked. Current principal and LP fees reconciled to treasury balances. Activated cancellation refunds remained unavailable. |

The tests read the real pool price, position liquidity and fee-growth snapshots, independently calculate rounded principal and accrued fees, and compare both vault and core balance changes. Caller impersonation isolates rejected callback fields and reentry during transfers. The fixture shares the prior activation setup, supports upward as well as downward swaps, and extends the token transfer probe to exercise nested manager calls. The existing lifecycle assertions run against the operation-tagged hook context. [Manager tests](../test/ManagerOperations.t.sol) · [Lifecycle regression](../test/AgreementLifecycle.t.sol)

## Size and replay

The previous vault used 21,743 runtime bytes, leaving 2,833 bytes. The constructor now creates a fixed, stateless OpeningQuote for the existing opening-band calculation and seed inspection. The vault makes read-only calls to its immutable address. Funding, activation, management, settlement and terminal authority stay in the vault. The original math libraries and pinned dependency notices are preserved. [OpeningQuote](../src/OpeningQuote.sol) · [M1 attribution](../experiments/m1/README.md#attribution-and-license-scope)

Use the [pinned root setup](../README.md#setup), then run from the repository root

```bash
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 -vv
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --match-test testSecondRerangeLegOneUnitShortRestoresEverythingAndRetries -vvvv
forge build --offline --use ~/.svm/0.8.26/solc-0.8.26 src/AgreementVault.sol --sizes
forge fmt --check src test
(cd experiments/m1 && sha256sum -c SHA256SUMS)
```

The pinned root suite passed 92 tests across eight suites (77 existing and 15 manager tests, zero failed or skipped, exit 0). Both fuzz tests ran 256 inputs. The independent opening-grid check, Solidity format check and all five M1 import hashes passed. [SHA-256 manifest](../experiments/m1/SHA256SUMS)

| Product | Runtime bytes | Forge initcode bytes | Initcode with fixed constructor arguments |
| --- | ---: | ---: | ---: |
| AgreementVault | 22,947 | 34,165 | 34,453 |
| ServiceHook | 1,390 | 1,807 | 1,935 |
| CompensationEscrow | 1,887 | 2,161 | 2,289 |
| OpeningQuote | 4,895 | 4,921 | 4,921 |

All four products fit the normal 24,576-byte runtime and 49,152-byte initcode limits under the existing compiler profile. The vault constructor arguments occupy nine ABI words. The hook and escrow each take four, and the helper takes none.

Principal exit assumes working core and vault contracts, transferable principal tokens, chain inclusion and settlement. A pending manager transaction can precede termination in chain order. The activated budget remains locked pending the service clock, earned reserves, claims and post-activation refunds. A1 and preliminary A2/A3 remain open.
