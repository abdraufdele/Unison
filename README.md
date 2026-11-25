# Unison

A treasury hires one manager for 300 seconds in one fixed-fee Uniswap v4 pool. It puts 2,000 mock A and 2,000 mock B under bounded management and funds a separate 100 B pay budget. **A second earns pay when the vault’s one position covers the fixed opening band, meets the minimum liquidity and contains the pool’s actual stored tick.** An unattended position can earn every second.

The hook observes third-party swaps as they happen and admits a vault-authorized liquidity addition once. In one local closeout, **180 qualifying seconds in a 300-second period earned 60 B**. The manager had received 40 B when the next claim failed. The treasury still withdrew its assets and collected a 40 B refund. Escrow kept the remaining 20 B owed to the manager and paid it when the route reopened. Inspect the two failed receipts and the withdrawals at blocks 29–36. [Payment run](docs/LOCAL-VIEWER.md#run-the-payment-failure-journey)

**What changed in the comparison?** The matched retainer delivered the same liquidity, fills, fees and principal across seven scenarios. Both arrangements allowed independent exit. The demonstrated difference is onchain payment for seconds of agreed service. Its value to a particular buyer remains open. [Matched results and costs](docs/M6-COMPARISON.md)

[Three-minute judge route and timed pitch](docs/M8-DEMO.md) · [Judge evidence and questions](docs/M8-JUDGE.md) · [Submission checklist](docs/M8-SUBMISSION.md)

## How one second becomes payable

Both parties accept the same terms hash before funding. At activation a fresh opening observation fixes the band for the whole period, [−120, 120) at parity. The permitted position must cover that band and hold at least 100,000,000,000 raw liquidity units. Compare the stored tick to the **position** edges, lower inclusive and upper exclusive. Tick 120 stops the seed earning. After a permitted extension to [−180, 180), the same tick qualifies. [Rules](src/ServiceRange.sol) · [Separate extension run](docs/LOCAL-VIEWER.md#permitted-manager-rerange-on-a-fresh-run)

| Component | Responsibility |
| --- | --- |
| ServiceHook | Authenticates PoolManager and pool. Before an add it checks the vault sender and consumes the exact grant. After a swap it credits elapsed time under the old condition, then reads core tick and liquidity for the installed position. The clock clips time at termination or scheduled end. [Hook](src/ServiceHook.sol) |
| AgreementVault | Owns the core position for the treasury. Binds pool, owner, ticks and salt. Checks caller, terms, inventory, range, price, amount, time and cooldown bounds. The vault must checkpoint **before** changing liquidity and install the confirmed position afterward. It revokes manager authority at termination or expiry. Treasury can remove liquidity, collect fees and withdraw idle assets in kind. [Vault](src/AgreementVault.sol) · [Closeout tests](docs/CLOSEOUT.md) |
| CompensationEscrow | Holds the funded budget separately. Earned base units equal `floor(funded budget × cumulative qualifying seconds / original duration)`. A claim pays earned less already paid to the fixed manager recipient. After close, the fixed treasury recipient can pull only the unearned budget less prior refunds. A failed transfer preserves the right to retry. [Escrow](src/CompensationEscrow.sol) |
| Local viewer | Reads terms, core position, time and balances at one block. A statement reconciles intervals and transfers to contract reads and labels the projected tail since the last checkpoint. Its fixed local actors submit transactions and display receipts. [Viewer and JSON export](docs/LOCAL-VIEWER.md#agreement-statement-and-json-export) |

## Evidence and limits

- **Measured cost.** In M6’s interrupted 300-second period with an outward swap, a return and a post-expiry swap, Unison used **9,405,354 more gas** than the bounded retainer. That includes one dedicated deployment per arm and its lifecycle transactions. Shared infrastructure and fixture costs are itemized separately. Treasury bore 9,190,339 extra gas, manager 70,909 and traders 144,106. The 40 B refund redistributes the existing budget. [Payer ledger and workload](docs/M6-COMPARISON.md#cost-by-payer-and-economic-hurdle)
- **Local engineering.** The recorded root suite passed 115 tests. Two author rounds on a provisioned WSL2 host reproduced three paths each. Chromium rechecked the patched viewer. Independent reproduction, customer acceptance, buyer economics and a narrated video remain pending. The implementation is now on the default [main branch](https://github.com/abdraufdele/Unison), integrated from development with a regular merge preserving individual commit history. [Author receipts](docs/A6-AUTHOR-REHEARSAL.md) · [Dependency assessment](docs/VIEWER-DEPENDENCIES.md) · [Independent checklist](docs/A6-REVIEWER.md) · [Latest local recheck](docs/TECHNICAL-RECHECK.md)
- **Limits.** The treasury bears market and inventory risk. The clock measures the agreed position condition. It can pay through external price drift and says nothing about profit, effort or guaranteed execution. Exit needs working vault, hook and core contracts, transferable principal tokens, chain progress and inclusion. The demo blocks one escrow-to-manager route. A global token freeze could block principal too. Only local mock assets and a mock opening source were exercised. [Service specification](docs/SERVICE-SPEC.md) · [Closeout assumptions](docs/CLOSEOUT.md)

## Setup

Use a fresh directory on a provisioned Linux x86-64 host. The rehearsed toolchain used WSL2 Ubuntu 24.04.3, Forge/Anvil 1.8.7 at `985eeea031d79922cd654d4e94e6c3701e1c7d73`, native solc 0.8.26, Python 3.12.3 with Web3.py 7.13.0, Node 22.19.0 and npm 11.21.3. This checkout pins the viewer revision revalidated after the dependency update. Keep the judge documents open on development. [Tool prerequisites and setup deviations](docs/A6-AUTHOR-REHEARSAL.md#setup-and-deviations)

```bash
git clone --branch development --single-branch https://github.com/abdraufdele/Unison.git unison-judge
cd unison-judge
git switch --detach a3c5173d9546d017ba322b66ea8096eabdd8ba55
```

From that root, fetch the pinned source into the unused vendor directory. The subshell stops at the first failed check. The Foundry profile selects Cancun, via IR and optimizer 200.

```bash
(
  set -eu
  cd experiments/m1
  sha256sum -c SHA256SUMS
  git init -q vendor/v4-core
  git -C vendor/v4-core remote add origin https://github.com/Uniswap/v4-core.git
  git -C vendor/v4-core fetch --depth 1 origin e50237c43811bd9b526eff40f26772152a42daba
  git -C vendor/v4-core checkout --detach FETCH_HEAD
  test "$(git -C vendor/v4-core rev-parse HEAD)" = e50237c43811bd9b526eff40f26772152a42daba
  test "$(git -C vendor/v4-core rev-parse HEAD:lib/solmate)" = 4b47a19038b798b4a33d9749d25e570443520647
  git -C vendor/v4-core submodule update --init --depth 1 -- lib/solmate
  test "$(git -C vendor/v4-core/lib/solmate rev-parse HEAD)" = 4b47a19038b798b4a33d9749d25e570443520647
  test -z "$(git -C vendor/v4-core status --porcelain)"
  test -z "$(git -C vendor/v4-core/lib/solmate status --porcelain)"
)
```

### Tests and viewer build

Run from the checkout root using the native compiler at the indicated path. The M6 checker reads the published CSVs offline.

```bash
(
  set -eu
  export FOUNDRY_PROFILE=default
  forge --version | grep -F 985eeea031d79922cd654d4e94e6c3701e1c7d73
  anvil --version | grep -F 985eeea031d79922cd654d4e94e6c3701e1c7d73
  c1_solc=~/.svm/0.8.26/solc-0.8.26
  printf '%s  %s\n' d5f23436f443edb85d8e76906d12f0a86ce0490e7663a9e608efeb7a93f149ef "$c1_solc" | sha256sum -c -
  python3 scripts/check_opening_grid.py
  forge fmt --check src test
  forge test --offline --use "$c1_solc" -vv
  python3 -B experiments/m6/check.py
  forge build --offline --use "$c1_solc" experiments/m6/Comparison.sol test/fixtures/CustodyFixture.sol test/fixtures/MockOpeningReferenceAdapter.sol experiments/m1/vendor/v4-core/src/PoolManager.sol
  python3 -B scripts/viewer/artifacts.py --check
  npm --prefix viewer ci
  npm --prefix viewer run build
)
```

### Run the interactive demo

In terminal one at the checkout root, start the local chain and wait for **Ready**.

```bash
python3 -Bu scripts/viewer/demo.py
```

In terminal two at the same root, serve the built page.

```bash
npm --prefix viewer run preview
```

Open `http://127.0.0.1:5173/`, check the funded run ID and select **Use this demo run**. Follow the payment path in the timed script. In the launcher prompt, `reset <full-current-run-id>` replaces that disposable fixture. Copy its actual ID, then confirm a new funded ID before choosing a different path. Enter `stop` in the launcher and press Ctrl-C in the preview terminal to finish. The runbook includes the pinned local Chromium install and automated browser commands. [Viewer controls and replay](docs/LOCAL-VIEWER.md) · [Timed demo](docs/M8-DEMO.md)

## Reuse and licenses

Unison’s C1 vault, service accounting, escrow and viewer build on the project’s preserved M1 direct-core experiment. M1 obtained unmodified upstream dependencies from the Essentials checkout. No Essentials hook implementation was imported. Uniswap v4-core supplies PoolManager (BUSL-1.1) and libraries including StateLibrary and FullMath (MIT). Solmate supplies Owned (AGPL-3.0-only). Preserve file-specific notices. The frontend uses React, React DOM, viem and Vite (MIT), TypeScript and Playwright Core (Apache-2.0), plus separately licensed transitive packages. [M1 provenance and license texts](experiments/m1/README.md#attribution-and-license-scope) · [Opening math credits](docs/OPENING-REFERENCE.md) · [Viewer dependencies](viewer/package-lock.json)


### Native WSL tools and demo scope

In WSL, check `command -v node npm` and `node -v` before the viewer commands. Both executables must resolve to the Linux installation, not Windows executables under `/mnt/c/`. Activate the documented Node version through your Linux version manager if necessary. A Windows npm selected from WSL can launch CMD against a UNC path and fail before TypeScript runs.

The browser is a fixed-actor local demonstration starting after acceptance and funding by the launcher. Draft creation/revision, separate wallet acceptance, approvals and funding are implemented/tested contract operations, not a complete browser onboarding workflow. General wallet connection and arbitrary manager requests are outside this frontend.

Mutation replay scripts use standard GNU `grep`; ripgrep is not required. Baseline success, successful mutant compilation and the exact intended assertion remain required.
