# Unison

**Define the job. Verify delivery. Pay what was earned.**

A proposed treasury-owned Uniswap v4 liquidity-service agreement. One treasury hires one manager for one position and one fixed period. A separate budget pays for agreed qualifying service; termination preserves earned obligations and supports independent principal recovery.

## Status

The narrow experimental MVP is local-only. The repository includes the verified source of the bounded M1 compatibility/accounting experiment. The original Windows experiment has been reproduced on native WSL. The local C1 vault records two-party acceptance, funds principal and compensation atomically, and supports cancellation before activation. The treasury can recover idle pair assets independently of the escrow refund. Activation, management, earned compensation and active-period closeout remain pending. Customer acceptance and economic advantage still require evidence.

Start with [PLAN.md](PLAN.md). Working rules: [AGENTS.md](AGENTS.md). Optional workflow: [docs/BUILDING.md](docs/BUILDING.md). Actual experimental result and limits: [docs/M1-STATUS.md](docs/M1-STATUS.md).

## Next task

Implement the local M2 activation prerequisites against the pinned M1 pool. Validate the accepted pool and opening reference, available funding and seed feasibility before opening the single position. Evaluate customer feedback on C1 and preliminary comparison/cost evidence in parallel with local engineering. [M1 provenance and scope](experiments/m1/README.md)

## Scope and limits

Fixed-band liquidity-time measures a contractual position condition, not profit, manager effort, guaranteed trade depth or continuous fair market value. Qualifying passive liquidity earns payment. Exit assumes functioning contracts/core/chain and transferable principal assets.

## Setup

The root contracts and Forge fixtures use native Forge 1.8.7 (`985eeea031d79922cd654d4e94e6c3701e1c7d73`) and Linux solc 0.8.26+commit.8a97fa7a. They require no external Solidity libraries. Use the cached native compiler at the path below and the checked-in default Foundry profile (Cancun, via IR, optimizer 200). From the repository root run

```bash
forge --version
~/.svm/0.8.26/solc-0.8.26 --version
sha256sum ~/.svm/0.8.26/solc-0.8.26
forge fmt --check src test
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 -vv
(cd experiments/m1 && sha256sum -c SHA256SUMS)
```

The expected native compiler SHA-256 is `d5f23436f443edb85d8e76906d12f0a86ce0490e7663a9e608efeb7a93f149ef`. The isolated M1 suites have their own dependencies and replay commands. [Pinned M1 replay procedure](experiments/m1/REPLAY.md) and [WSL replay result](experiments/m1/WSL-RESULT.md).

## Local custody fixture

The treasury creates a draft vault, deploys the escrow with that vault, token B and both fixed recipients, then revises the draft to bind the escrow. Both parties accept the resulting hash. A temporary draft address has no funding authority. At funding the vault checks the escrow's compiled runtime hash, all four bindings, and zero prior credits and refunds. The escrow constructor sets its bindings once. This setup uses the existing draft revision path and needs no factory. [Custody fixture](test/fixtures/CustodyFixture.sol)

The treasury approves the vault for 2,000,000,000 A units and 2,100,000,000 B units. Before the original cutoff, one call to `fund(hash)` sends 2,000,000,000 units of each token to the vault and 100,000,000 B units directly to escrow. Funding verifies both token decimals, each debit and receipt, and the final balances. C1 assumes truthful balance reporting and ordinary transferable, non-rebasing local tokens. [Funding tests](test/AgreementVaultFunding.t.sol)

The treasury can cancel Draft, Accepted or Funded. Anyone can cancel from the cutoff onward. Cancellation moves no tokens. After cancellation, the treasury calls `withdrawIdle()` for the current pair, including gifts. Anyone can call `refund()` to return the credited budget to the treasury. Direct escrow gifts stay in escrow. A failed pull can be retried, and an empty pull pays zero. [Cancellation and recovery tests](test/AgreementVaultCancellation.t.sol)
