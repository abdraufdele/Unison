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

Stage two kept all compiled selector sets and runtime lengths above. Private Solidity names use lower camelCase. NatSpec explains custody, checkpoint ordering, identity and test scenarios. The external constant getters preserve their uppercase ABI spellings. Solidity constructors, Foundry setUp, cheatcodes and protocol callbacks keep their required signatures. React components use JSX capitalization. Python's __init__ and BaseHTTPRequestHandler's do_GET, do_POST, do_OPTIONS and log_message keep their dispatch names. M1 and the historical M6 comparison harness retain their original conventions.


## Discovery and scope

Foundry discovers one directory per category. Unit covers standalone band math and vault-only consent. Integration covers cross-contract funding, reference and closeout and the pinned PoolManager scenarios. The three fuzz entries use independent assertions about a nonmatching terms hash, outward grid minimality and a generated service history. The service-clock and consent fixtures contain shared setup and expected-state helpers. The shared Vm interface sits in test/helpers. Mutation scripts select one exact integration test in a fresh ignored workspace.

The stateful ServiceHandler owns the fixture treasury, submits permitted operations as the named manager and challenges permissions from an unrelated caller. It integrates elapsed qualification from the previous core state and reconciles both the fixed manager's actual receipts and outstanding escrow rights. Each sequence begins activated. Random handler calls advance the clock, adjust actual liquidity, attempt unauthorized management or pull account balances. A missing expected rejection or any unexpected handler revert fails the campaign. The 32-seed deterministic corpus continues to cover fee-bearing reranges, splits, atomic failures, blocked payouts and terminal receipt ordering independently.

Final discovery at the separated layout found 18 unit, 94 integration, three fuzz and one invariant entry. All 116 passed. Each fuzz entry ran 256 inputs. At seed 0x19112026, 64 runs × depth 64 selected adjustLiquidity 1,009 times, advanceTime 1,022, challengeCaller 1,041 and settleBudget 1,024. All 4,096 handler calls succeeded with zero unexpected reverts or discards. The caller challenge requires an inner NotManager rejection on every call. Adjustments after expiry require an inner InvalidPeriod rejection. Successful handlers include those checked rejection paths. No failing sequence was produced. The deterministic corpus remains four integration entry points covering 32 fixed seeds.

| Current product artifact | Creation bytes | Runtime bytes | SHA-256 of creation code including metadata |
|---|---:|---:|---|
| AgreementVault | 39,556 | 23,891 | 30c4d54123d93766586116dae00978c22f405b9630ec51673585c457c60e2b89 |
| ServiceHook | 5,155 | 4,738 | da9dc8e3c9cb420c38db2925025d8e6cea2d1267ab9c75a794de6c65861ffa81 |
| CompensationEscrow | 3,260 | 2,986 | 70cad68ae1590a497da6f51532b6fe8dd9af12f1589368143b1e145b67b78e84 |
| OpeningQuote | 4,921 | 4,895 | 512f6bcac3d42fbea2192373b0974905b9412d019e5cadcc3d7fa64dad7a04a5 |

The vault retains 685 bytes of EIP-170 headroom. The viewer build identity after extracting the shared Vm interface is `601a90c0da0d875cdc932a268b3db065b065b91c813ff23a958b77b8cc175719`. New deployments mine hook addresses from these artifacts. Existing manifests bind their own build.
