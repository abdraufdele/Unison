# C1 activation preflight

Anyone may call `AgreementVault.preflightActivation(expectedHash)` to inspect a funded agreement. It returns the fresh observation, candidate band, manager and full PoolKey, PoolId, stored tick, Q64.96 square-root price, seed liquidity, gross A/B requirements and the three actual custody balances. It writes no state and transfers no tokens. A swap, cancellation, changed balance, reference update or elapsed cutoff can invalidate the result before execution. [Vault](../src/AgreementVault.sol) and [pool reader](../src/SeedPool.sol).

## Checks at the time of the call

- The agreement must be Funded on its creation chain, with the expected current hash, both current acceptances and time strictly before the original cutoff.
- The vault must have credited exactly 2,000,000,000 units of each token and still hold the full agreed inventory. The escrow must match the compiled implementation and its four bindings, have credited 100,000,000 B, hold at least that amount, and have refunded zero. Principal gifts increase the observed balance. Only funded credits establish the agreement's rights. Only vault balances can supply the seed.
- The vault calls the existing opening-reference validator. It derives the band from the current accepted adapter observation. The seed is 100,000,000,000 raw L, within the C1 minimum and maximum. [Reference rules and mock trust boundary](OPENING-REFERENCE.md)
- Core indexes pools by the hash of ordered currencies, fee, spacing and hook. The reader builds that key from the accepted bindings, checks the fixed 3000 fee and spacing 60, and reads slot 0 at that ID on the accepted manager. It requires a nonzero initialized price, matching stored LP fee, code at the accepted hook, and exactly the before-add-liquidity and after-swap address flags. Both seed ticks must be usable on this grid and have capacity for the added gross liquidity.
- Eligibility uses the stored tick in `[lower, upper)`. For an eligible seed, A is the upward-rounded amount0 delta from actual sqrt price to upper sqrt price, and B is the upward-rounded amount1 delta from lower sqrt price to actual sqrt price. Both use the pinned core's TickMath and SqrtPriceMath. Each leg must fit its gross-input cap and available vault inventory.

## Actual modifyLiquidity results

Each row uses six-decimal base units. The test compares the quote to signed principal from core (caller delta less accrued fees), checks the core's token receipts, and reads back the test payer's position with the full seed L.

| Pool state | Band | Quoted A, B | Core principal delta A, B |
| --- | --- | ---: | ---: |
| Parity, tick 0 | [−120, 120) | 598,173,777 / 598,173,777 | −598,173,777 / −598,173,777 |
| Price between ticks 23 and 24 | [−120, 120) | 480,748,617 / 715,736,985 | −480,748,617 / −715,736,985 |
| Exactly at lower tick −120 | [−120, 120) | 1,199,947,203 / 0 | −1,199,947,203 / 0 |
| Downward swap to parity, stored tick −1 | [−240, 0) | 0 / 1,192,769,434 | 0 / −1,192,769,434 |

At an initialized upper tick of 120 the parity band was ineligible. In the last row a real downward swap crossed initialized tick zero and stopped at its sqrt price. That state also rejected a fresh band of [0, 240). Using the tick inferred from price would have reversed both decisions.

A separate test payer owned the trial position and settled with its own mock tokens. Each positive leg was tried one unit short from an equivalent snapshot. All six short trials reverted on the actual token debit and rolled back the position. All four exact trials settled with zero payer inventory left. The vault retained its principal and the escrow kept its budget. [Core tests](../test/ActivationPreflight.t.sol) and [test hook and payer](../test/fixtures/CoreSeedHarness.sol).

## Reproduction and limits

Use the [root setup and version checks](../README.md#setup). The complete native suite and the four trace cases were run with

```bash
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 -vv
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 --match-contract ActivationPreflightTest \
  --match-test 'test(FundedParity|InteriorUses|LowerInclusive|DownwardCross)' -vvvv
(cd experiments/m1 && sha256sum -c SHA256SUMS)
```

The root suite passed 66 tests, including 15 preflight tests. Both existing fuzz tests ran 256 inputs. The four selected cases emitted the `CoreSeedCompared` receipts above. Each command exited 0 and all five M1 checks matched.

The tests instantiate the pinned PoolManager in Forge. A test-only stateless hook is placed at the required address bits with `etch`. It acknowledges callbacks and admits every LP. Other negative fixtures simulate a custody loss or inconsistent escrow getters. No pool storage was fabricated for the quote comparisons. Outside this fixture the reader relies on the accepted manager implementing the pinned core layout. Key identity, flags and present code cannot establish hook admission, callback authorization, vault wiring or a single-use operation context.

PoolManager and Pool's per-tick capacity calculation carry BUSL-1.1 notices. StateLibrary, TickMath and SqrtPriceMath carry MIT notices. The pinned manager uses Solmate Owned (AGPL-3.0-only). Upstream source and licenses remain in the pinned checkout. The harness follows the direct core owner and settlement path documented in the M1 experiment. [M1 provenance and upstream licenses](../experiments/m1/README.md#attribution-and-license-scope).

Next design the terminal recovery path before placing principal in liquidity. Atomic treasury activation must rerun the preflight in the same transaction, bind and authenticate the vault-owned operation, reconcile the actual seed debits and resulting position, and persist activation only on success.
