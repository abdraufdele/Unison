# C1 development evidence

The starting development revision was `192bb1c2283e6effa839922b2a1ed72650044f1c`, verified against origin with a clean tree. Foundry 1.8.7 (`985eeea`), solc 0.8.26+commit.8a97fa7a, Cancun, via IR and optimizer 200. Core e50237c43811bd9b526eff40f26772152a42daba and Solmate 4b47a19038b798b4a33d9749d25e570443520647. Viewer uses the npm lock with Node 22.19.0 and npm 11.21.3.

| C1 promise | Implementing calls | Evidence selection (append to `forge test --offline --match-test`) | Boundary |
|---|---|---|---|
| Both parties consent to the same revision | revise, accept, termsHash | testRevisionClearsBothAndRestoringTermsRequiresFreshDecisions | Local actors |
| Separate exact deposits | fund, credit | testExactDepositsCreditsAndReceiptsWithPriorGifts | Plain transferable tokens |
| Fresh reference, outward-rounded band | previewOpeningReference, preflightActivation | testFeedVectorsAndRepresentableExtremes | Fixed scale, mock observation |
| Seed uses actual core price and tick | activate, unlockCallback, beforeAddLiquidity | testDownwardCrossToPriceOneUsesStoredMinusOne | Pinned core layout |
| Bounded atomic rerange | rerange | testSecondRerangeLegOneUnitShortRestoresEverythingAndRetries | Available inventory |
| Qualification belongs to the current identity | beforeAdjustment, installPosition, afterSwap | testFullRemovalPreservesOldIntervalAndReopeningUsesFreshSalt | Vault-owned position only |
| Cumulative entitlement with original duration | projectedSeconds, checkpoint, earned | testOneThenThreeSecondsAndPartitionIndependentEntitlement | Base units, floor |
| Refund preserves earned rights | refund, claim | testTerminalRefundLeavesUnpaidEarnedReserve | Exact debit and receipt |
| Revocation and independent principal receipt | terminate, finalizeExpiry, exitLiquidity, withdrawIdle | testExpiredTreasuryReceivesPrincipalWithManagerRouteBlocked | Functioning principal tokens, core and chain |
| Complete cash and fee ledger | claim, refund, withdrawIdle | 'testCloseoutSeeds.*' | Deterministic generated corpus, 32 seeds alternating early and expiry close |

Baseline comprised 115 tests in 12 suites, including three parameterized tests at 256 runs each. The four closeout corpus entries execute fixed seeds. The local deployment fixture in experiments/m6/run.py uses owned Anvil IPC, direct treasury creation, CREATE2 hook mining and separate actor transactions. scripts/viewer/demo.py binds the funded deployment to the browser endpoint and run marker. scripts/viewer/artifacts.py authenticates source hashes and compiler settings before emitting the reader ABI. The original prover commands and historical browser and mutation evidence are in [technical recheck](TECHNICAL-RECHECK.md). Original M6 receipts remain under experiments/m6/results.

Baseline product runtime sizes in bytes were 23,891 (AgreementVault), 4,738 (ServiceHook), 2,986 (CompensationEscrow) and 4,895 (OpeningQuote). Internal libraries each compile to a 57-byte stub. See the [compiled selector inventory](SELECTORS.md) for the ABI at this revision.
