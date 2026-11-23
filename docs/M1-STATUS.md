# M1 compatibility/accounting status

## Verified bounded result

The isolated experiment executed on 19 November 2026 used real local Uniswap v4 PoolManager operations, a separate direct-core vault, authenticated hook callbacks and a separate compensation contract.

- Original suite: 19 passing tests; 128 randomized sequences × 32 steps.
- Assessment: six additional tests against unchanged implementation passed after correcting an assessment-only exact-tick expectation. Failed assessment trace was retained.
- Controlled 300-second scenario: 200 qualifying seconds paid 200 mock payment tokens; 100 remained.
- Omitting the pre-liquidity-change checkpoint caused the intended duration assertion to fail.
- Controlled extra execution gas: outward 97,462; return 57,636; post-term 26,904. Diagnostic samples, not full receipt costs or a representative mean.

## Pins and source identity

- Local experiment source commit: 2a511e26fe289e3323dccae6a933053353dae9ce (no public remote established).
- v4 core: e50237c43811bd9b526eff40f26772152a42daba.
- solmate: 4b47a19038b798b4a33d9749d25e570443520647.
- Foundry 1.8.7, commit 985eeea031d79922cd654d4e94e6c3701e1c7d73.
- Solidity 0.8.26+8a97fa7a; Cancun; optimizer 200; viaIR; dynamic test linking disabled.
- Experiment.sol SHA-256: fb53eefed7c1cc394e5b44bd7407b49799bc07f1e1cd029a34793ed8a555a6ed.

## Unfinished and unproved

No full acceptance/funding prerequisite, unearned refund path or complete payment-failure closeout exists. The residual 100 tokens cannot be recovered through the experiment's supported functions. Correct clock behavior depends on vault checkpoint discipline; the hook does not independently enforce it.

No demonstrated customer acceptance, total-cost advantage, security audit, deployed product or fresh-machine full-product setup. A qualifying passive position earns payment. The metric does not prove profit, skill or continuously market-relative depth.

## Evidence handling

Original source, runners, logs, assessment and manifests remain in the separate preserved research archive under research/2026-11-19-compatibility, alongside M1-ASSESSMENT.md and docs/UNISON-M1-EXPERIMENT.md. The working experiment folder is named Unison-compatibility, a sibling of the proposed implementation folder.

This summary alone is NOT a reproducibility package. Before relying on M1 in the implementation, retrieve the preserved evidence, verify hashes/pins and import selected source/tests under an explicit reuse record; preserve failures and licensing. Do not recreate unsupported passing claims from this text.
