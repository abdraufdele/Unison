# C1 development evidence

The starting development revision was `192bb1c2283e6effa839922b2a1ed72650044f1c`, verified against origin with a clean tree. Foundry 1.8.7 (`985eeea`), solc 0.8.26+commit.8a97fa7a, Cancun, via IR and optimizer 200. Core e50237c43811bd9b526eff40f26772152a42daba and Solmate 4b47a19038b798b4a33d9749d25e570443520647. Viewer uses the npm lock with Node 22.19.0 and npm 11.21.3.

| C1 promise | Implementing calls | Evidence selection (append to `forge test --offline --match-test`) | Boundary |
|---|---|---|---|
| Both parties consent to the same revision | revise, accept, termsHash | testRevisionClearsBothAndRestoringTermsRequiresFreshDecisions | Local actors |
| Separate exact deposits | fund, credit | testExactDepositsCreditsAndReceiptsWithPriorGifts | Plain transferable tokens |
| Fresh reference, outward-rounded band | previewOpeningReference, preflightActivation | testFeedVectorsAndRepresentableExtremes | Fixed scale, mock observation |
| Seed quote uses actual core price and stored tick | preflightActivation, OpeningQuote.seed | testDownwardCrossToPriceOneUsesStoredMinusOne | Pinned core layout |
| Activation installs the vault-owned seed | activate, unlockCallback, beforeAddLiquidity | testActivationOwnsExactSeedAndFixedObservation | C1 pair and pinned core |
| Bounded atomic rerange | rerange | testSecondRerangeLegOneUnitShortRestoresEverythingAndRetries | Available inventory |
| Qualification belongs to the current identity | beforeAdjustment, installPosition, afterSwap | testFullRemovalPreservesOldIntervalAndReopeningUsesFreshSalt | Vault-owned position only |
| Cumulative entitlement with original duration | projectedSeconds, checkpoint, earned | testOneThenThreeSecondsAndPartitionIndependentEntitlement | Base units, floor |
| Refund preserves earned rights | refund, claim | testTerminalRefundLeavesUnpaidEarnedReserve | Exact debit and receipt |
| Revocation and independent principal receipt | terminate, finalizeExpiry, exitLiquidity, withdrawIdle | testExpiredTreasuryReceivesPrincipalWithManagerRouteBlocked | Functioning principal tokens, core and chain |
| Complete cash and fee ledger | claim, refund, withdrawIdle | 'testCloseoutSeeds.*' | Deterministic generated corpus, 32 seeds alternating early and expiry close |

Baseline comprised 115 tests in 12 suites, including three parameterized tests at 256 runs each. The four closeout corpus entries execute fixed seeds. The local deployment fixture in experiments/m6/run.py uses owned Anvil IPC, direct treasury creation, CREATE2 hook mining and separate actor transactions. scripts/viewer/demo.py binds the funded deployment to the browser endpoint and run marker. scripts/viewer/artifacts.py authenticates source hashes and compiler settings before emitting the reader ABI. The original prover commands and historical browser and mutation evidence are in [technical recheck](TECHNICAL-RECHECK.md). Original M6 receipts remain under experiments/m6/results.

Baseline product runtime sizes in bytes were 23,891 (AgreementVault), 4,738 (ServiceHook), 2,986 (CompensationEscrow) and 4,895 (OpeningQuote). Internal libraries each compile to a 57-byte stub. See the [compiled selector inventory](SELECTORS.md) for the ABI at this revision.

Stage two kept all compiled selector sets and runtime lengths above. Private Solidity names use lower camelCase. NatSpec explains custody, checkpoint ordering, identity and test scenarios. The external constant getters preserve their uppercase ABI spellings. Solidity constructors, Foundry setUp, cheatcodes and protocol callbacks keep their required signatures. React components use JSX capitalization. Python's __init__ and BaseHTTPRequestHandler's do_GET, do_POST, do_OPTIONS and log_message keep their dispatch names. Web3's make_request override retains its provider dispatch name. M1 and the historical M6 comparison harness retain their original conventions.


## Discovery and scope

Foundry discovers one directory per category. Unit covers standalone band math and vault-only consent. Integration covers cross-contract funding, reference and closeout and the pinned PoolManager scenarios. The three fuzz entries use independent assertions about a nonmatching terms hash, outward grid minimality and a generated service history. The service-clock and consent fixtures contain shared setup and expected-state helpers. The shared Vm interface sits in test/helpers. Mutation scripts select one exact integration test in a fresh ignored workspace.

The stateful ServiceHandler owns the fixture treasury, submits permitted operations as the named manager and challenges permissions from an unrelated caller. It integrates elapsed qualification from the previous core state and reconciles both the fixed manager's actual receipts and outstanding escrow rights. Each sequence begins activated. Random handler calls advance the clock, adjust actual liquidity, attempt unauthorized management or pull account balances. A missing expected rejection or any unexpected handler revert fails the campaign. The 32-seed deterministic corpus continues to cover fee-bearing reranges, splits, atomic failures, blocked payouts and terminal receipt ordering independently.

The executed root run reported **116 passed, 0 failed, 0 skipped across 16 suites**. Separate category runs passed 18 unit, 94 integration, three fuzz and one invariant. The empty-cache discovery check below independently verified the names and source paths. Each fuzz entry ran 256 inputs. At seed 0x19112026, 64 runs × depth 64 selected adjustLiquidity 1,009 times, advanceTime 1,022, challengeCaller 1,041 and settleBudget 1,024. All 4,096 handler calls succeeded with zero unexpected reverts or discards. The caller challenge requires an inner NotManager rejection on every call. Adjustments after expiry require an inner InvalidPeriod rejection. Successful handlers include those checked rejection paths. No failing sequence was produced. The deterministic corpus remains four integration entry points covering 32 fixed seeds.

| Current product artifact | Creation bytes | Runtime bytes | SHA-256 of creation code including metadata |
|---|---:|---:|---|
| AgreementVault | 39,556 | 23,891 | 30c4d54123d93766586116dae00978c22f405b9630ec51673585c457c60e2b89 |
| ServiceHook | 5,155 | 4,738 | da9dc8e3c9cb420c38db2925025d8e6cea2d1267ab9c75a794de6c65861ffa81 |
| CompensationEscrow | 3,260 | 2,986 | 70cad68ae1590a497da6f51532b6fe8dd9af12f1589368143b1e145b67b78e84 |
| OpeningQuote | 4,921 | 4,895 | 512f6bcac3d42fbea2192373b0974905b9412d019e5cadcc3d7fa64dad7a04a5 |

The vault retains 685 bytes of EIP-170 headroom. The viewer build identity after extracting the shared Vm interface is `601a90c0da0d875cdc932a268b3db065b065b91c813ff23a958b77b8cc175719`. New deployments mine hook addresses from these artifacts. Existing manifests bind their own build.

## Fresh comparison

`make m6-run OUTPUT=.local/ops/refactor-m6` executed matched local arms A (static), B (bounded retainer) and C (Unison) across seven schedules using the current creation bytecode above. The independent checker reconciled 21 lifecycles, 45 orders and 150 receipt rows including setup. Order and outcome tables matched the historical tables byte for byte. Interrupted service delivered 180 qualifying seconds, 60 B earned and 40 B refundable.

| Interrupted workload, including dedicated deployment | Treasury gas | Manager gas | Trader gas | Total |
|---|---:|---:|---:|---:|
| Static A | 1,559,695 | 0 | 433,537 | 1,993,232 |
| Bounded retainer B | 3,146,099 | 117,649 | 433,537 | 3,697,285 |
| Unison C | 12,336,486 | 188,558 | 577,643 | 13,102,687 |
| C minus B | 9,190,387 | 70,909 | 144,106 | 9,405,402 |

The earlier interrupted C-minus-B result was 9,405,354 gas. The new local premium is 48 gas higher. Shared infrastructure and fixture-only operations are itemized separately. These figures are local EVM gas units. Buyer-specific valuation, chain fees and independent A6 reproduction remain open.

| Fresh CSV | SHA-256 |
|---|---|
| gas.csv | f0e9baebb16a37d31f84dee12fd806a3447445a49234f0396eb9f6acc4d2690b |
| orders.csv | 7e4478328663c008448d3cc8c05ec7400c83b3c20ea75202586763a4a68ec039 |
| outcomes.csv | babf621d1785ab59607ab997e611f19ff1f1402c9222c344c5b7caf86a94cdd7 |

Use a fresh empty output directory to repeat the comparison. The preserved results under experiments/m6/results still describe the historical build.

## Operator and browser checks

The final Chromium build exported eight statements covering funded, active, manager rerange, termination, refund, repeated refund, interrupted swap and expiry. Missing, duplicate and misordered event results were rejected against receipts. The payment journey observed failed transfers, successful independent principal recovery and later payment of the reserved balance. The swap journey stopped and resumed accrual on actual core tick changes. All exercised the build identity above. Repeat with `make browser` after `make viewer-build`.

The Foundry constructor script simulates a direct treasury CREATE. The Foundry lifecycle script rehearses consent through independent closeout. The Python driver acquires real addresses from mined receipts in the selected simulation, mines the hook salt, journals partial progress and verifies final bindings. The operator CLI filters reads by ABI mutability and dispatches explicit actions by role. Both scripts and the local acceptance sequence ran on disposable signers. The [network checks](NETWORK-CHECKS.md) record chain-specific results. The [selector inventory](SELECTORS.md) maps each callable entry and generated getter to its use.

The current development surface has 47 vault, 36 hook, 15 escrow and two quote selectors. The compiler-derived check also covers the token, opening-reference and settlement-reader interfaces. It resolves active source declarations and their compilation targets, so cached artifacts from removed declarations do not enter the inventory. The independent opening-grid calculation reproduced all three digests checked by the unit tests.

## Mutation acceptance

Each runner first executes its selected test on the correct build, verifies identical test sources in the isolated workspace and compiles the changed contract. It checks the failing test name, error arguments and runner-specific trace evidence. The aggregate Make check repeated all four with the following outcomes. Compiler and baseline exited 0 and each selected mutant test exited 1.

| Make target | Expected failure observed |
|---|---|
| mutation-clock | OldIntervalLost(100, 0) |
| mutation-reserve | ReserveStolen(20000000, 0) |
| mutation-revocation | ExpiredPositionChanged(100000000000, 0) |
| mutation-payment | PrincipalReceiptShort(1900054977, 1401826223) |

## Isolated build and final operator result

An empty Foundry output directory and an empty compiler cache produced a successful native solc 0.8.26 build of 81 files. Fresh JSON discovery matched the multiset of current test names **and source paths** exactly, with 18 unit, 94 integration, three fuzz and one invariant entry. For 25 declarations covering the product, core, deployment fixtures and comparison arms, the comparison checked ABI, method identifiers, exact creation and runtime bytes, and compiler source identities. All matched across the retained previous build, the isolated build and the installed output. Every source named by the installed artifact metadata exists. The obsolete ICancellation artifact is absent. The viewer's generated bindings and build identity matched the installed artifacts.

Repeat the isolated build and discovery from the repository root. The subshell keeps the alternate paths local to the check.

```sh
(
  set -eu
  mkdir -p .local/verification
  fresh=$(mktemp -d "$PWD/.local/verification/fresh-XXXXXXXX")
  export FOUNDRY_OUT="$fresh/out" FOUNDRY_CACHE_PATH="$fresh/cache"
  forge build --offline --use "$HOME/.svm/0.8.26/solc-0.8.26" src test script experiments/m6/Comparison.sol experiments/m1/vendor/v4-core/src/PoolManager.sol
  forge test --offline --use "$HOME/.svm/0.8.26/solc-0.8.26" --list --json > "$fresh/discovery.json"
)
```

The first expanded operator assertion indexed a named ABI result numerically. That acceptance run exited 2 from Make. The corrected assertion checks both the qualified flag and zero failure bits. On the fresh artifacts, `make check-actions` exited 0. The terminal statement at block 33 reconciled 153 qualifying seconds over the original 300-second term. Of 100 funded B, the manager received 51 B and the treasury received a 49 B refund. Earned unpaid, claimable, refundable, escrow balance and owned liquidity were all zero. The exporter reconciled the liquidity exit and idle withdrawal to the fixed treasury using product events and token balance changes. The separate Chromium release replay exited 0, including the reader state vectors, fault cases, stale manifest and all eight exports.

## Judge receipt references

Both local runs used a 100 B budget and an original 300-second term. Run IDs scope the block numbers below. The browser uses fixed roles and scripted time advances. The operator sequence reads the live local block time, so its observed 153 seconds describe this particular run.

| Retained run | What to inspect |
|---|---|
| Operator acceptance `0xe7eae1a1434bcba9421a78786c29ce1176d3e7b34a9dd38dfab93c8227e44a37` | Terminal statement at block 33. The manager received 51 B for 153 qualifying seconds. The treasury received the 49 B refund after principal recovery. Owned liquidity, escrow balance and outstanding rights were zero. Replay with `make check-actions`. |
| Scripted browser payment failure `0x78f860bb0decbd70364d500e72f53f5186d90c941647033533c4c794b78faaef` | Block 26 paid 40 B. The claim reverted at 29 and termination froze 180 qualifying seconds at 30. At 33 the treasury received 2,100.346049 A and 1,900.054977 B with the route blocked. At 34 the 40 B refund left 20 B reserved. Block 36 paid that 20 B to the manager, bringing receipts to 60 B. The two repeat pulls transferred zero. Replay with `make browser`. |

The retained author logs are local verification outputs. The public [original two-round receipt table](A6-AUTHOR-REHEARSAL.md#run-identities-and-receipts) identifies its own revision and six other runs. New reviewer runs generate their own identities and receipts.
