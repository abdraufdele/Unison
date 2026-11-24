# C1 activation and principal recovery

## Recovery design

| Reachable state | Close action | Treasury principal | Compensation custody |
| --- | --- | --- | --- |
| Draft, Accepted, Funded | Treasury may cancel. Anyone may cancel from the original cutoff. | After cancellation, pull idle pair assets. | Only cancellation makes credited funding refundable. |
| Active | Treasury may terminate before the scheduled end. | Principal remains in idle balances and the vault-owned core position until close. | The separate budget stays in escrow. |
| Terminated | Early stop time is the termination timestamp. | Withdraw idle balances and remove the live position independently, in either order. Withdraw again for later proceeds. | Active-period settlement is unavailable in this slice. |
| Expired | Effective at the scheduled end. Anyone may record expiry later with that original timestamp. | Same exit rights as Terminated, even before expiry is recorded. | Same compensation boundary as Terminated. |

Activation permanently closes cancellation. Otherwise the cancellation-only escrow would mistake a previously active agreement for an unactivated one and release its entire budget. Closing the period records the reason and time without transferring tokens or reading the oracle. A failed removal or withdrawal reverts its own effects and leaves it retryable. Principal exit depends on functioning core and vault contracts, transferable pair tokens and chain inclusion. LP fees and current token quantities belong to the treasury.

The activation slice preceded the service clock. M3 now freezes qualifying seconds on exit. The activated budget stays in escrow pending earned-reserve accounting, claims and post-activation refunds. [Service-clock evidence](SERVICE-CLOCK.md)

## How the local integration works

The test creates the vault, real pinned PoolManager and two six-decimal mock currencies. It hashes the product hook's creation code and constructor arguments, searches CREATE2 salts for the exact low-bit mask `0x0840`, runs the constructor and checks the predicted address. The constructor binds one vault, core and PoolId computed from the complete fixed-fee key including the hook itself. These constructor-set fields have no setters. The treasury revises the draft to include that hook before both roles accept. The older preflight-only fixture uses a separate test stub. [Product hook](../src/ServiceHook.sol) and [integration fixture](../test/AgreementLifecycle.t.sol).

Activation reads a fresh funded preflight, then checks the hook's runtime code hash, all three bindings and an empty admission context. The vault computes the canonical escrow and hook code hashes at construction. Its unlock request commits to the position bounds, salt and signed liquidity delta. Only the configured core can consume that outstanding request. Inside the seed unlock the vault arms exactly one positive add leg immediately before calling core. The hook checks the core, full key, actual vault sender and hash of the expected parameters, then consumes the grant. The sign distinguishes seed from terminal removal. The hook exposes no pool initiator. Authenticated after-swap calls from the configured pool accept external traders without writing service entitlement.

The vault synchronizes currencies, transfers the actual debts to core, and verifies each debit, receipt and settled amount. It checks both seed legs against the gross quote, zero fees on the fresh identity, actual position L, the final pool tick and price, and the separate escrow balance. A successful transaction fixes the opening observation, band, first salt, start and scheduled end. The full identity uses the accepted manager, PoolId, vault owner, lower/upper ticks and salt. Full removal records the two principal and fee amounts and retires the live position by clearing its L. The salt and fixed band remain available to identify the historical position. [AgreementVault](../src/AgreementVault.sol).

Negative tests use caller impersonation to vary callback fields independently, adversarial local token routes to fail a transfer or attempt nested calls, and failing external reads to exercise recovery. The main activation, swap and removal tests run the real product constructor, callbacks and core accounting. This implementation inherits the M1 direct-owner and sync/settle/take approach. The pinned dependencies retain their original file-specific notices. [M1 attribution](../experiments/m1/README.md#attribution-and-license-scope).

## Executed local recovery

On the pinned Forge EVM the CREATE2 constructor deployed the hook at `0x48c0e43D9f2A97356FaFefB78C59C2085504C840`. The initialized pool ID was `0x29914b07400f34898d8fc44fc8fc41493a0ac000f45c0301045920ef4f5ff01c`. The seed position under the vault's address, ticks [−120, 120) and salt 1 held exactly 100,000,000,000 L. The period started at 10,000 and was scheduled to end at 10,300.

| Base units | A | B |
| --- | ---: | ---: |
| Vault inventory before seed | 2,000,000,000 | 2,000,000,000 |
| Actual seed expenditure | 598,173,777 | 598,173,777 |
| Idle withdrawal after termination | 1,401,826,223 | 1,401,826,223 |
| Removed principal after swap to tick −20 | 698,218,788 | 498,228,754 |
| Treasury LP fees | 301,038 | 0 |
| Total received by treasury | 2,100,346,049 | 1,900,054,977 |

The fixture independently calculated removal principal from the actual square-root price with core's removal rounding. It calculated fees from the position's last recorded fee growth, current fee growth inside the band and actual L. Both legs matched the exit receipt, core debits and vault receipts. Termination at 10,010 moved no funds. The treasury withdrew idle assets before removal and withdrew again for proceeds. The activated budget remained 100,000,000 B in escrow. No manager claim exists to exercise in this slice.

A separate run observed Expired at exactly 10,300, exited before finalization, then persisted 10,300 as the stop at 10,377. Failure on the second seed payment reverted the first payment, the core position, both operation contexts and all activation fields. Removal and withdrawal failures also left their respective rights retryable. Independent additions failed at the hook and an external trader's real swap succeeded.

## Reproduce

Use the [pinned root setup](../README.md#setup). From the repository root run

```bash
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 -vv
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --match-test testEarlyTerminationIndependentExitAndWithdrawalsAfterSwap -vvvv
forge build --offline --use ~/.svm/0.8.26/solc-0.8.26 src/AgreementVault.sol --sizes
forge fmt --check src test
(cd experiments/m1 && sha256sum -c SHA256SUMS)
```

The complete suite passed 77 tests across seven suites, with zero failures or skips (exit 0). All 66 previous tests passed. The two existing fuzz tests ran 256 inputs each. The trace replay, formatting, size check and all five imported-file hashes passed (exit 0). Product runtime sizes were 21,743 bytes for AgreementVault, 1,158 for ServiceHook and 1,887 for CompensationEscrow, under the normal 24,576-byte limit. The root configuration retains its original code-size settings.
