# C1 opening reference

`AgreementVault.previewOpeningReference()` returns one validated observation and a candidate half-open band. It reads the adapter bound to the current Accepted or Funded revision exactly once. The preview writes no agreement state. Draft revisions still require two fresh acceptances. The canonical terms encoding and rules identifier stay at C1 v1. [Vault](../src/AgreementVault.sol) and [accepted rules](SERVICE-SPEC.md#opening-reference-and-purchased-depth).

## Observation and trust

The sole adapter method takes no arguments and returns nine static ABI words. The vault rejects a failed read or an unexpected payload length. ABI decoding checks the field encodings. The adapter asserts source identity, base A, quote B, their whole-token decimals, feed decimals, signed answer, observation timestamp and completion. The vault compares those identities and scales to the accepted terms, checks decimals on both token contracts, requires completion and a positive answer, and checks a nonzero timestamp with age from 0 through 60 seconds inclusive against block time. [Adapter interface](../src/IOpeningReferenceAdapter.sol)

The local mock lets a test publish an observation. A consistent assertion can still contain a false price or time. Trust in its source, observation process and completion flag comes from the accepted adapter. A live source, its provenance and its freshness policy remain open. [Mock adapter](../test/fixtures/MockOpeningReferenceAdapter.sol) and [validation tests](../test/OpeningReference.t.sol).

## Exact price and supported domain

For integer answer `a`, raw B units per A unit are `a × 10^6 / (10^8 × 10^6) = a / 10^8`. C1 cancels the equal token scales exactly. Express the two targets with denominator `D = 10^10` and integer numerators `99a` and `101a`. Only the accepted 6/6/8 decimals, spacing 60 and 100-basis-point half-width are supported. Search uses v4's usable ticks from −887220 to 887220. The accepted maximum band width is 480 ticks.

The positive feed domain is **1 through 33514072460913245910620992844148187695034543842**, inclusive. Its upper bound is the floor of `D × (10001/10000)^887220 / 101`. The next answer needs an upper edge beyond the last usable tick. At the low end one feed unit already exceeds the minimum pool price. The implementation guards multiplication by 101, rejects an unavailable edge and checks that the width is positive and within the accepted limit. [Band implementation](../src/OpeningBand.sol)

For grid price `g(t) = (10001/10000)^t` and integer target numerator `n`, the predicate `floor(D × g(t)) >= n` is exactly equivalent to `g(t) >= n/D`. Binary search finds the first such tick in at most 15 comparisons per edge. This is the upper tick. For a strict crossing its predecessor is the lower tick. At equality both round to the same tick for that target. The search bisects grid indices with a nonnegative offset, including below zero.

**Which equalities are possible?** For positive nonzero grid ticks the reduced denominator of the price is `10000^t`. For negative grid ticks it is `10001^abs(t)`. Neither divides D on the spacing-60 grid. At tick zero, synthetic target `D/D` is exactly one. Neither 99 nor 101 divides D, so neither feed target can hit even that boundary. Valid feed tests straddle negative, zero and positive crossings with adjacent answers. Synthetic target tests place the numerator at D−1, D and D+1.

## Integer certificate for each comparison

TickMath uses fixed-point multiplication and rounds up its final conversion to a Q64.96 square-root price. Squaring that returned integer would compare against the encoded core ratio. C1 specifies the rational power above. We reuse TickMath's grid bounds and FullMath's 512-bit multiply/divide and certify the price separately.

1. Every usable tick is even. Compute lower and upper bounds on `g(t/2)` by exponentiation by squaring at integer scale `S = 4 × 10^57`. The positive base is exactly representable. For negative ticks start with the floor and ceiling of `S × 10000/10001`. All factors are positive, so rounding each lower product down and each upper product up preserves containment.
2. The exponent is at most 443610 and takes at most 19 iterations. Each intermediate represents at most that exponent. On the positive side the true scaled half-power is below `7.36 × 10^76`. Each upward division adds less than one scaled unit. Positive factors are at least S, so an expanded product of k factors has relative inflation bounded by `(1 + 1/S)^(2k)`, below `1 + 10^-50` here. Negative-side bounds stay at or below S. The quotients and rescaling additions fit uint256. FullMath handles products in 512 bits.
3. Divide the lower bound down and the upper bound up by `4 × 10^14` to reach scale `10^43`. Square each and divide by `10^76` to obtain the two floors at scale D. Both squares use 512-bit intermediates. Return the integer only if the two floors agree. This check succeeded for every C1 grid point in the root suite.

## Independent verification and use at activation

The Python standard-library oracle walks the grid in steps of 60 from zero in both directions. Each step uses the exact fraction `10001^60 / 10000^60` or its reciprocal and outward integer bounds at 90 decimal places. It independently certifies all 29,575 floors and emits three SHA-256 digests of ascending 32-byte values. Forge recomputes the digests from Solidity and checks explicit feed vectors. Its fuzz property checks both outer inequalities and both neighboring ticks. The exhaustive scan runs only in verification. [Independent oracle](../scripts/check_opening_grid.py) and [Forge tests](../test/OpeningBand.t.sol).

| Feed answer | Independently derived band |
| ---: | --- |
| 1 | [−184320, −184080) |
| 100,000,000 | [−120, 120) |
| 125,000,000 | [2100, 2340) |
| Maximum supported answer | [886980, 887220) |

Future activation must call the validator inside the activation transaction, recheck the current agreement hash, Funded state, available balances and original cutoff, and validate the actual pool configuration, execution tick and seed feasibility. Persist that transaction's observation, normalized price and edges only when the seed succeeds. Subsequent accounting and exit use stored state. An earlier preview is a snapshot and can expire.

## Dependency and reproduction

From the root use the commands in the [root setup](../README.md#setup). The relative remapping resolves to the existing clean M1 checkout of Uniswap v4-core at `e50237c43811bd9b526eff40f26772152a42daba`. For a fresh checkout follow the upstream clone and detached checkout in the [pinned replay procedure](../experiments/m1/REPLAY.md#tools-and-inputs). The opening-band calculation imports FullMath and TickMath with its BitMath and CustomRevert imports. The separate [activation preflight tests](ACTIVATION-PREFLIGHT.md) also compile PoolManager and its pinned Solmate dependency. The four opening-band dependencies carry MIT identifiers. The checkout retains the copyright notice, permission text, FullMath's credit to Remco Bloemen and BitMath's Solady attribution. [Pinned upstream license](https://github.com/Uniswap/v4-core/blob/e50237c43811bd9b526eff40f26772152a42daba/licenses/MIT_LICENSE).
