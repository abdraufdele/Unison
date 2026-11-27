# C1 compensation and independent receipt

One fully funded C1 agreement credits 100,000,000 base units of the six-decimal mock B token for an original duration of 300 seconds. The credited deposit is F. For an activated agreement F equals its agreed budget B. With cumulative qualifying seconds Q, successful claims C and successful refunds R, the escrow uses

```text
earned E          = floor(B × Q / original duration)
claimable/reserve = E − C
refundable        = F − E − R when terminal, zero otherwise
accounted         = F − C − R
```

The only new vault method, `settlementContext()`, returns the authenticated hook, original duration and effective terminal flag. A zero clock denotes an unactivated agreement. Cancellation is terminal and earns zero. The vault checks the escrow runtime hash, constructor-bound vault, token and both recipients before crediting the exact agreed budget. Both parties' accepted bindings are fixed at funding. Successful activation checks the hook runtime hash, vault, PoolManager and full PoolId and establishes the seed before publishing the clock. A lookalike returning the right addresses and 300 seconds failed activation and created zero entitlement. [Vault](../src/AgreementVault.sol) · [Funding checks](../test/integration/AgreementVaultFunding.t.sol)

The escrow calls only its constructor-bound vault for this context. It uses the original scheduled end minus start, checks Q ≤ D, and applies the pinned v4-core MIT FullMath.mulDiv once to the cumulative seconds. Before activation it skips clock reads entirely. `earned()`, `claimable()`, `reserved()` and `refundable()` use the clipped projection. `fundedBudget()`, `claimed()` and `refunded()` are persisted counters. `accounted()` excludes gifts. The hook separately exposes persisted `qualifyingSeconds()` and projected `projectedSeconds()`. [Escrow](../src/CompensationEscrow.sol) · [Service clock](SERVICE-CLOCK.md)

Anyone can trigger a claim when active or terminal, or a refund when terminal, including at scheduled expiry before finalization. Each eligible pull checkpoints the clock if activated. A positive transfer goes to the fixed recipient and emits its receipt. Both pulls share the escrow lock. Any transfer failure or debit/credit mismatch rolls back the counter, token movement and that call's checkpoint. An eligible zero pull returns zero. Direct gifts have no payout or sweep path. [Exact token helpers](../src/ExactToken.sol)

During a manager removal the vault has already credited the old interval. A transfer callback can trigger a claim using the installed clock at the same timestamp. The regression changed actual L to half the minimum while the hook still held the old observation. A nested refund was rejected, the claim paid exactly the old interval's 10 B, and the vault installed the new L after settlement. Attempts to reenter both pulls during the payouts were rejected. Swaps, close, removal and principal withdrawal have no new payment call.

## Reconciled payments

| Case | Manager receipt | Treasury budget receipt |
| --- | ---: | ---: |
| Full passive service, first claim at elapsed 350 | 100 B | 0 |
| Swaps at 90 and 210, Q = 180 at exact expiry | 60 B | 40 B |
| Early termination at Q = 120 | 40 B | 60 B |
| Claim at Q = 1 then Q = 3 | 333,333 then 666,667 base units | Active refund unavailable |
| Cancel before funding / after full funding | 0 / 0 | 0 / 100 B |

The interrupted test replayed both terminal pull orders from one snapshot. Each left the same recipient balances and 17 donated base units in escrow with accounted balance zero. Split claims matched a single claim at Q = 3. A false return, malformed success word, short receipt and excessive debit each rolled back the claim. An exact transfer with no return data succeeded. [Settlement regressions](../test/integration/CompensationSettlement.t.sol) · [Cancellation regressions](../test/integration/AgreementVaultCancellation.t.sol)

| Worked manager failure | Earned B | Claimed B | Unpaid reserve B | Refunded B | Accounted B |
| --- | ---: | ---: | ---: | ---: | ---: |
| Successful claim at Q = 120 | 40 | 40 | 0 | 0 | 60 |
| Blocked additional claim and same-timestamp termination at Q = 180 | 60 | 40 | 20 | 0 | 60 |
| Treasury receives the final unearned refund | 60 | 40 | 20 | 40 | 20 |
| Restored manager route pays the outstanding claim | 60 | 60 | 0 | 40 | 0 |

Only the escrow-to-manager transfer route was blocked. Adapter calls failed independently. With those faults in place, core removal returned 698,218,788 A and 498,228,754 B principal units plus 301,038 A fee units. Including idle assets, treasury received 2,100,346,049 A and 1,900,054,977 B units before its separate 40,000,000-unit refund. The restored manager route paid 20,000,000 units. Repeated pulls paid zero.

A separate fixture blocked only escrow-to-treasury B transfers at Q = 120. The failed 60 B refund left R at zero. Treasury still received 1,999,999,999 units of each principal token, and manager received the 40 B claim while the refund was blocked. Restoring the refund route delivered the original 60 B. These exits assume functioning vault, core, hook, transferable principal tokens and chain inclusion.

## Verification and replay

The [reserve mutation replay](../scripts/check_reserve_mutation.sh) first passed the unchanged full-reserve test (exit 0). In an isolated copy it replaced total earnings with prior claims in the refund subtraction. The build succeeded (exit 0). After the refund actually transferred, the test read the escrow token balance and failed with `ReserveStolen(20000000, 0)` (exit 1). The full 20 B unpaid reserve had left custody. The replay verified that the test trees matched. Mutation source, artifacts and raw logs remain ignored.

Use the [pinned native setup](../README.md#setup). The root suite passed 109 tests in ten suites, with zero failures or skips and exit 0. Nine settlement tests joined the 100 existing cases. Wrong-hash, opening-grid and service-clock sequence fuzzing each ran 256 inputs using seed `0x19112026`. A separate two-test failure/exit trace passed with exit 0.

```bash
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --fuzz-seed 0x19112026 -vv
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --match-test 'test(ManagerPaymentFailureCloseoutWithFeeBearingPrincipal|RefundFailurePreservesIndependentPrincipalAndManagerReceipt)' -vvvv
forge build --offline --use ~/.svm/0.8.26/solc-0.8.26 src/AgreementVault.sol --sizes
bash scripts/check_reserve_mutation.sh
forge fmt --check src test
python3 scripts/check_opening_grid.py
(cd experiments/m1 && sha256sum -c SHA256SUMS)
```

| Product | Runtime bytes | Creation bytecode bytes | Actual initcode with arguments |
| --- | ---: | ---: | ---: |
| AgreementVault | 23,891 | 39,556 | 39,844 |
| CompensationEscrow | 2,986 | 3,260 | 3,388 |
| ServiceHook | 4,738 | 5,155 | 5,283 |
| OpeningQuote | 4,895 | 4,921 | 4,921 |

The vault, escrow, hook and helper have nine, four, four and zero static ABI constructor words respectively. All four fit the normal runtime and initcode limits. The vault retains 685 runtime bytes. The size build, native formatting, opening grid and five [original M1 hashes](../experiments/m1/SHA256SUMS) passed with exit 0. The subsequent [M5 closeout review](CLOSEOUT.md) records the broader lifecycle reconciliation and remaining targeted mutations. Customer acceptance, comparative economics and a reproducible full demonstration remain open.
