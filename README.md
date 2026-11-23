# Unison

**Define the job. Verify delivery. Pay what was earned.**

A proposed treasury-owned Uniswap v4 liquidity-service agreement. One treasury hires one manager for one position and one fixed period. A separate budget pays for agreed qualifying service; termination preserves earned obligations and supports independent principal recovery.

## Status

The narrow experimental MVP is local-only. The repository includes the verified source of the bounded M1 compatibility/accounting experiment. The original Windows experiment has been reproduced on native WSL. The local AgreementVault now records two-party acceptance of exact C1 terms. Funding, activation, refunds and closeout are pending. Customer acceptance and economic advantage still require evidence.

Start with [PLAN.md](PLAN.md). Working rules: [AGENTS.md](AGENTS.md). Optional workflow: [docs/BUILDING.md](docs/BUILDING.md). Actual experimental result and limits: [docs/M1-STATUS.md](docs/M1-STATUS.md).

## Next task

Implement the local M2 funding transition with atomic receipts and a post-funding revision lock. Evaluate customer feedback on C1 and preliminary comparison/cost evidence in parallel with local engineering. [M1 provenance and scope](experiments/m1/README.md)

## Scope and limits

Fixed-band liquidity-time measures a contractual position condition, not profit, manager effort, guaranteed trade depth or continuous fair market value. Qualifying passive liquidity earns payment. Exit assumes functioning contracts/core/chain and transferable principal assets.

## Setup

From the repository root, run the [acceptance tests](test/AgreementVaultAcceptance.t.sol) using the pinned WSL toolchain.

```bash
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 -vv
```

The experiment has a [pinned Linux setup and replay procedure](experiments/m1/REPLAY.md). The [WSL replay report](experiments/m1/WSL-RESULT.md) records the executed results.
