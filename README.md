# Unison

**Define the job. Verify delivery. Pay what was earned.**

A proposed treasury-owned Uniswap v4 liquidity-service agreement. One treasury hires one manager for one position and one fixed period. A separate budget pays for agreed qualifying service; termination preserves earned obligations and supports independent principal recovery.

## Status

The narrow experimental MVP is local-only. The repository includes the verified source of the bounded M1 compatibility/accounting experiment. The original Windows experiment has been reproduced on native WSL. The local C1 vault records two-party acceptance, funds principal and compensation atomically, and supports cancellation before activation. The treasury can recover idle pair assets independently of the escrow refund. The treasury can now activate the agreement against the pinned v4 pool, seed a vault-owned position, and recover idle tokens, remaining liquidity and LP fees after termination or expiry. Activation reruns the opening and seed preflight. The named manager can add, remove, reopen, or atomically rerange one vault-owned position within C1 limits. The hook admits each authorized add leg once. Termination and exact expiry revoke management. The service clock tracks cumulative qualifying seconds against the actual core position and clips at termination or scheduled end. Anyone can trigger a fixed-manager claim for cumulative earned service or a fixed-treasury refund of the final unearned balance. Unpaid earnings stay reserved. Customer acceptance and economic advantage still require evidence.

Start with [PLAN.md](PLAN.md). Working rules: [AGENTS.md](AGENTS.md). Optional workflow: [docs/BUILDING.md](docs/BUILDING.md). Actual experimental result and limits: [docs/M1-STATUS.md](docs/M1-STATUS.md).

## Local agreement viewer

Inspect a funded agreement and its service clock, compensation rights, pool position and actual custody at a single block. The loopback page operates fixed local demo actors through a payment failure, treasury exit, refund and later manager claim. A separate fresh run demonstrates swap interruption and recovery. Build and download a block-pinned statement to reconcile service intervals, transfers and outstanding rights. [Setup, start, stop and reset](docs/LOCAL-VIEWER.md)

For an independent fresh-checkout replay, use the [A6 developer checklist](docs/A6-REVIEWER.md). It includes the public revision, expected results and a blank reviewer record.

## Next task

Evaluate whether both roles accept C1 and whether their reconciliation costs justify the measured premium. The local M6 comparison found identical delivery under matched management and different payment for interrupted service. [M6 results and cost thresholds](docs/M6-COMPARISON.md)

## Scope and limits

Fixed-band liquidity-time measures a contractual position condition, not profit, manager effort, guaranteed trade depth or continuous fair market value. Qualifying passive liquidity earns payment. Exit assumes functioning contracts/core/chain and transferable principal assets.

## Setup

The root contracts and Forge fixtures use native Forge 1.8.7 (`985eeea031d79922cd654d4e94e6c3701e1c7d73`) and Linux solc 0.8.26+commit.8a97fa7a. The root preflight tests instantiate the real v4 PoolManager. On a fresh clone, obtain the pinned v4-core checkout and its Solmate submodule using the [M1 setup](experiments/m1/REPLAY.md#tools-and-inputs). Python 3 runs the independent grid check using its standard library. Use the cached native compiler at the path below and the checked-in default Foundry profile (Cancun, via IR, optimizer 200). From the repository root run

```bash
forge --version
~/.svm/0.8.26/solc-0.8.26 --version
sha256sum ~/.svm/0.8.26/solc-0.8.26
test "$(git -C experiments/m1/vendor/v4-core rev-parse HEAD)" = e50237c43811bd9b526eff40f26772152a42daba
test -z "$(git -C experiments/m1/vendor/v4-core status --porcelain)"
test "$(git -C experiments/m1/vendor/v4-core/lib/solmate rev-parse HEAD)" = 4b47a19038b798b4a33d9749d25e570443520647
test -z "$(git -C experiments/m1/vendor/v4-core/lib/solmate status --porcelain)"
python3 scripts/check_opening_grid.py
forge fmt --check src test
forge test --offline --use ~/.svm/0.8.26/solc-0.8.26 -vv
(cd experiments/m1 && sha256sum -c SHA256SUMS)
```

The expected native compiler SHA-256 is `d5f23436f443edb85d8e76906d12f0a86ce0490e7663a9e608efeb7a93f149ef`. The isolated M1 suites have their own dependencies and replay commands. [Pinned M1 replay procedure](experiments/m1/REPLAY.md) and [WSL replay result](experiments/m1/WSL-RESULT.md).

The [M5 closeout matrix](docs/CLOSEOUT.md) maps the terminal rights and callback checks to executed tests, including the stateful balance reconciliation and mutation results. The [M4 settlement report](docs/COMPENSATION.md) records payout interfaces, exact base-unit transfers, failure recovery and reserve-mutation replay. The [service-clock evidence](docs/SERVICE-CLOCK.md) covers third-party swap intervals, stateful reconciliation, terminal freezing and the ordering mutation. The [manager-operations evidence](docs/MANAGER-OPERATIONS.md) covers operation bounds, the opening-quote helper, atomic rollback, and independently reconciled principal and LP fees. The [activation and principal recovery report](docs/ACTIVATION-RECOVERY.md) covers the product hook, real vault-owned position, independent exit and the M2 custody boundary. The [activation preflight report](docs/ACTIVATION-PREFLIGHT.md) records the core reads, seed deltas and limits of the fixture. The [opening-reference implementation note](docs/OPENING-REFERENCE.md) gives the input bounds, rounding proof, mock trust assumptions, upstream credits and how to use the result at activation.

## Local custody fixture

The treasury creates a draft vault, deploys the escrow with that vault, token B and both fixed recipients, then revises the draft to bind the escrow. Both parties accept the resulting hash. A temporary draft address has no funding authority. At funding the vault checks the escrow's compiled runtime hash, all four bindings, and zero prior credits and refunds. The escrow constructor sets its bindings once. This setup uses the existing draft revision path and needs no factory. [Custody fixture](test/fixtures/CustodyFixture.sol)

The treasury approves the vault for 2,000,000,000 A units and 2,100,000,000 B units. Before the original cutoff, one call to `fund(hash)` sends 2,000,000,000 units of each token to the vault and 100,000,000 B units directly to escrow. Funding verifies both token decimals, each debit and receipt, and the final balances. C1 assumes truthful balance reporting and ordinary transferable, non-rebasing local tokens. [Funding tests](test/AgreementVaultFunding.t.sol)

The treasury can cancel Draft, Accepted or Funded. Anyone can cancel from the cutoff onward. Cancellation moves no tokens. After cancellation, the treasury calls `withdrawIdle()` for the current pair, including gifts. Anyone can call `refund()` to return the credited budget to the treasury. Direct escrow gifts stay in escrow. A failed pull can be retried, and an empty pull pays zero. [Cancellation and recovery tests](test/AgreementVaultCancellation.t.sol)
