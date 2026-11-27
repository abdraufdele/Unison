# Unison

A treasury hires one manager for 300 seconds in one fixed-fee Uniswap v4 pool. It puts 2,000 mock A and 2,000 mock B under bounded management and funds a separate 100 B pay budget. **A second earns pay when the vault’s one position covers the fixed opening band, meets the minimum liquidity and contains the pool’s actual stored tick.** An unattended position can earn every second.

The hook observes third-party swaps as they happen and admits a vault-authorized liquidity addition once. In one local closeout, **180 qualifying seconds in a 300-second period earned 60 B**. The manager had received 40 B when the next claim failed. The treasury still withdrew its assets and collected a 40 B refund. Escrow kept the remaining 20 B owed to the manager and paid it when the route reopened. Inspect the two failed receipts and the withdrawals at blocks 29–36. [Payment run](docs/LOCAL-VIEWER.md#run-the-payment-failure-journey)

**What changed in the comparison?** The matched retainer delivered the same liquidity, fills, fees and principal across seven scenarios. Both arrangements allowed independent exit. The demonstrated difference is onchain payment for seconds of agreed service. Its value to a particular buyer remains open. [Matched results and costs](docs/M6-COMPARISON.md)

[Final judge handoff](docs/M8-SUBMISSION.md#judge-handoff) · [Three-minute inspection](docs/M8-DEMO.md#three-minute-judge-inspection) · [Judge questions](docs/M8-JUDGE.md)

## How one second becomes payable

Both parties accept the same terms hash before funding. At activation a fresh opening observation fixes the band for the whole period, [−120, 120) at parity. The permitted position must cover that band and hold at least 100,000,000,000 raw liquidity units. Compare the stored tick to the **position** edges, lower inclusive and upper exclusive. Tick 120 stops the seed earning. After a permitted extension to [−180, 180), the same tick qualifies. [Rules](src/ServiceRange.sol) · [Separate extension run](docs/LOCAL-VIEWER.md#permitted-manager-rerange-on-a-fresh-run)

| Component | Responsibility |
| --- | --- |
| ServiceHook | Authenticates PoolManager and pool. Before an add it checks the vault sender and consumes the exact grant. After a swap it credits elapsed time under the old condition, then reads core tick and liquidity for the installed position. The clock clips time at termination or scheduled end. [Hook](src/ServiceHook.sol) |
| AgreementVault | Owns the core position for the treasury. Binds pool, owner, ticks and salt. Checks caller, terms, inventory, range, price, amount, time and cooldown bounds. The vault must checkpoint **before** changing liquidity and install the confirmed position afterward. It revokes manager authority at termination or expiry. Treasury can remove liquidity, collect fees and withdraw idle assets in kind. [Vault](src/AgreementVault.sol) · [Closeout tests](docs/CLOSEOUT.md) |
| CompensationEscrow | Holds the funded budget separately. Earned base units equal `floor(funded budget × cumulative qualifying seconds / original duration)`. A claim pays earned less already paid to the fixed manager recipient. After close, the fixed treasury recipient can pull only the unearned budget less prior refunds. A failed transfer preserves the right to retry. [Escrow](src/CompensationEscrow.sol) |
| Local viewer | Reads terms, core position, time and balances at one block. A statement reconciles intervals and transfers to contract reads and labels the projected tail since the last checkpoint. Its fixed local actors submit transactions and display receipts. [Viewer and JSON export](docs/LOCAL-VIEWER.md#agreement-statement-and-json-export) |

## Evidence and limits

- **Cost.** On the current build, the interrupted 300-second workload cost Unison **9,405,402 gas more** than the bounded retainer. This includes each arm’s dedicated deployment, an outward swap, a return and a post-expiry swap. Both delivered the same liquidity, fills and fees. The original M6 build measured 9,405,354 extra gas. The 40 B refund redistributes the funded budget. [Current payer totals](docs/DEVELOPMENT-EVIDENCE.md#fresh-comparison) · [Historical workload](docs/M6-COMPARISON.md#cost-by-payer-and-economic-hurdle)
- **Execution.** The author’s root run passed all 116 tests across 16 suites. A separate empty-cache build confirmed discovery. The release browser exported eight statements. The earlier two-round author rehearsal and its original revision remain available. Independent A6, customer decisions, buyer-specific economics and a narrated video are pending. [Current execution evidence](docs/DEVELOPMENT-EVIDENCE.md) · [Historical author receipts](docs/A6-AUTHOR-REHEARSAL.md) · [Independent checklist](docs/A6-REVIEWER.md)
- **Limits.** The treasury bears inventory risk. Exit needs functioning contracts, transferable principal assets, chain progress and transaction inclusion. The demo blocks only the escrow-to-manager route. Local and fork simulations used mock assets and a mock opening source. Pinned Unichain forks exercised the deployed cores on owned nodes. Public deployment and explorer verification remain unexecuted. Mainnet preparation requires a reviewed exact-transfer token pair and suitable independent opening reference. [Network checks](docs/NETWORK-CHECKS.md) · [Closeout assumptions](docs/CLOSEOUT.md)

## Setup

Use a fresh directory on a provisioned Linux x86-64 host. The rehearsed toolchain used WSL2 Ubuntu 24.04.3, Forge/Cast/Anvil 1.8.7 at `985eeea031d79922cd654d4e94e6c3701e1c7d73`, native solc 0.8.26, Python 3.12.3 with Web3.py 7.13.0, Node 22.19.0 and npm 11.21.3. Check out the implementation and independent reviewer pin `e14fb19801c9c3bede31b36d9cfeb2ad237c66f2`. Keep the current judge instructions open on development while running the pinned code. [Tool prerequisites and setup deviations](docs/A6-AUTHOR-REHEARSAL.md#setup-and-deviations)

```bash
git clone --branch development --single-branch https://github.com/abdraufdele/Unison.git unison-judge
cd unison-judge
git switch --detach e14fb19801c9c3bede31b36d9cfeb2ad237c66f2
git rev-parse HEAD
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

### Development commands

Run `make help` from the root for the supported command groups. After installing the locked viewer packages, `make sizes` checks deployment limits and ABI selectors. `make unit integration fuzz invariant` exercises the four test categories. `make dry-run-local` writes a fresh deployment manifest on a disposable node. `make check-actions` rehearses both actors, validates management calls and reconciles the final statement. Set the documented Chromium path to run `make check` including browser and mutation checks. The final local operator run reconciled 51 B paid and 49 B refunded after 153 qualifying seconds and treasury principal recovery. Setup, exact inputs, fork pins and execution results are in the [operator runbook](docs/OPERATIONS.md), [network checks](docs/NETWORK-CHECKS.md) and [development evidence](docs/DEVELOPMENT-EVIDENCE.md).

### Tests and viewer build

From the checkout root, use the Python dependencies pinned in `requirements-dev.txt`. On a freshly provisioned checkout, restore the locked viewer packages once. The M6 target verifies the published historical CSVs offline. To generate receipts for the pinned implementation, use the fresh comparison command in the runbook. [Python setup and command verification](docs/OPERATIONS.md)

```bash
make prerequisites
make viewer-install
make deps fmt-check sizes
make test SEED=0x19112026
make artifacts viewer-build m6
```

### Run the interactive demo

In terminal one at the checkout root, start the local chain and wait for **Ready**.

```bash
make demo
```

In terminal two at the same root, serve the built page.

```bash
make viewer-preview
```

Open `http://127.0.0.1:5173/`, check the funded run ID and select **Use this demo run**. Follow the payment path in the timed script. In the launcher prompt, `reset <full-current-run-id>` replaces that disposable fixture. Copy its actual ID, then confirm a new funded ID before choosing a different path. Enter `stop` in the launcher and press Ctrl-C in the preview terminal to finish. The runbook includes the pinned local Chromium install and automated browser commands. [Viewer controls and replay](docs/LOCAL-VIEWER.md) · [Timed demo](docs/M8-DEMO.md)

## Reuse and licenses

Unison’s C1 vault, service accounting, escrow and viewer build on the project’s preserved M1 direct-core experiment. M1 obtained unmodified upstream dependencies from the Essentials checkout. No Essentials hook implementation was imported. Uniswap v4-core supplies PoolManager (BUSL-1.1) and libraries including StateLibrary and FullMath (MIT). Solmate supplies Owned (AGPL-3.0-only). Preserve file-specific notices. The frontend uses React, React DOM, viem and Vite (MIT), TypeScript and Playwright Core (Apache-2.0), plus separately licensed transitive packages. [M1 provenance and license texts](experiments/m1/README.md#attribution-and-license-scope) · [Opening math credits](docs/OPENING-REFERENCE.md) · [Viewer dependencies](viewer/package-lock.json)


### Native WSL tools and demo scope

In WSL, check `command -v node npm` and `node -v` before the viewer commands. Both executables must resolve to the Linux installation, not Windows executables under `/mnt/c/`. Activate the documented Node version through your Linux version manager if necessary. A Windows npm selected from WSL can launch CMD against a UNC path and fail before TypeScript runs.

The browser is a fixed-actor local demonstration starting after acceptance and funding by the launcher. Draft creation/revision, separate wallet acceptance, approvals and funding are implemented/tested contract operations, not a complete browser onboarding workflow. General wallet connection and arbitrary manager requests are outside this frontend.

Mutation replay scripts use standard GNU `grep`; ripgrep is not required. Baseline success, successful mutant compilation and the exact intended assertion remain required.
