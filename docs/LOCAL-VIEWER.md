# Local agreement viewer

The viewer reads a single mock C1 agreement at one mined block. It opens in the accepted and fully funded state. The service clock shows the contract's projected entitlement at the displayed block alongside the last persisted checkpoint. Page load, polling and **Refresh reads** leave the chain at the same head. Select **Use this demo run** to operate the named local actors. [M6 comparison and economic limits](M6-COMPARISON.md)

## Start, inspect and stop

On a bandwidth-limited fresh checkout, the full upstream v4-core history can exceed a bounded fetch. The following alternative fetches the same core commit and the Solmate gitlink from upstream. Run this **before** the Forge build, from the Unison root with an unused vendor destination. The subshell returns to the Unison root for the viewer commands.

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

Use the [pinned root setup](../README.md#setup), the pinned core checkout and the existing M6 Python environment (Python 3.12, Web3.py 7.13.0). The checked tools were Anvil/Forge 1.8.7, Node 22.19.0 and npm 11.21.3. From the repository root, use the first command when the Forge artifacts are missing or their source inputs changed.

```bash
forge build --offline --use ~/.svm/0.8.26/solc-0.8.26 experiments/m6/Comparison.sol test/fixtures/CustodyFixture.sol test/fixtures/MockOpeningReferenceAdapter.sol experiments/m1/vendor/v4-core/src/PoolManager.sol
python3 -B scripts/viewer/artifacts.py --check
# On a fresh workstation, restore the pinned dependencies once. Reuse an existing install.
npm --prefix viewer ci
npm --prefix viewer run build
```

Start the fixture in a foreground terminal and wait for its Ready message.

```bash
python3 -Bu scripts/viewer/demo.py
```

From a second terminal at the repository root, serve the built page. Open `http://127.0.0.1:5173/` using that exact host. For frontend development, `npm --prefix viewer run dev` uses the same address and port. Use one frontend server at a time.

```bash
npm --prefix viewer run preview
```

The launcher reserves port 18547 before starting its own loopback-only Anvil with a private IPC socket and fresh disposable accounts. The runtime manifest is public-safe JSON held in memory at `http://127.0.0.1:18547/deployment.json`. It can be inspected with `curl -fsS http://127.0.0.1:18547/deployment.json`. An occupied port causes startup to fail. Leave its existing owner alone or use the already running viewer deliberately after checking the manifest and run ID.

Enter these commands **at the fixture prompt**. Local chain time advances only through the explicit setup actions in this fixture.

| Command | Effect |
| --- | --- |
| `inspect` | Independently read lifecycle, actual core position, balances, qualification and compensation with Web3.py. Quantities are raw base units. |
| `activate` | Treasury activates the funded agreement at chain time 2000. Mine one block at 2001 to expose six-decimal rounding. |
| `interrupt` | After activation the trader offers 700 B for A, limited at tick 120, at chain time 2090. |
| `terminate` | After activation treasury stops the period at 2180. Earned reserves and final unearned funds remain in escrow for inspection. |
| `reset <full-current-run-id>` | Verify the current endpoint, chain, anchor and onchain agreement ID. Close only the launcher's own child, then build a new funded deployment with a new identity. Copy the ID from this prompt or manifest. |
| `stop` | Shut down the read endpoint and its owned Anvil. Ctrl-C also closes this foreground launcher. Use Ctrl-C in the second terminal to stop Vite. |

Allow one refresh interval (eight seconds) after a command or select **Refresh reads**. A fresh run can have the same chain ID and block height as its predecessor. The launcher uses the vault's immutable random agreement ID as the onchain run marker. The manifest binds the loopback read endpoint, chain ID, marker, funded block number/hash, deployment addresses, runtime code hashes and a SHA-256 identity over the named compiled creation bytecodes. The vault's bytecode includes its constructor-created opening helper. The artifact loader checks source hashes and compiler settings. Export new read bindings deliberately with `python3 -B scripts/viewer/artifacts.py` after an intentional artifact change. [ABI exporter](../scripts/viewer/artifacts.py)

The browser accepts only this build and endpoint. It verifies the funded block anchor, code, vault marker, terms bindings and recipients, pins financial/core calls to the same block and rechecks that block hash. Changing the manifest clears the previous snapshot. Read failures mark retained same-run data stale. Identity or missing-code failures clear the financial display. The local gateway exposes four read RPC methods. Fixture transactions and time controls use the launcher's owned IPC connection. The control session uses an origin-bound, run-specific anti-CSRF token. Signers stay in the disposable Anvil. [Reader](../viewer/src/read.ts) · [Fixture launcher](../scripts/viewer/demo.py)

## Run the payment-failure journey

Open the agreement, verify its run ID under **Pool and deployment**, then select **Use this demo run**. Starting with the funded agreement, select each action in the payment column below in order. The launcher submits one fixed transaction per click. Follow the pending actor and action, then expand its mined receipt for the transaction hash, sender, target, block, time, result and reconciled balances. The service clock and custody panel refresh from the chain. An interrupted request can have an uncertain outcome. Refresh reads and inspect the latest receipt before proceeding.

The table records one Chromium author replay on 25 November 2026. The payment run was `0xe8bce929dc235adc9ca4a5e5599c06c3f554c86d9c01a318e829cfa11fef6344` on local chain 31337. Each hash identifies a local transaction in that run. Deployments generate fresh accounts, hashes and agreement IDs.

| Block | Chain seconds | Payment journey and observed result | Transaction hash |
| ---: | ---: | --- | --- |
| 23 | 2000 | Treasury activated. Block 24 was an explicit empty observation at +1 s. | `0x7e40368bb7c2a46ed2ebc5d911bad06e819f64440346af44926316780757f8ca` |
| 25 | 2120 | Trader offered 700 A toward tick −20. The position still qualified at Q=120. | `0x689a39207e46ebf19b13e27d79eb6a9533eae7c15948c7ebac1fe75f5509be63` |
| 26 | 2120 | Manager received 40 B. | `0xa36059dc9bea969cd363d8973e793c1ea86ec0f21383d7d8b1468807214764c7` |
| 27 | 2180 | Treasury checkpointed Q=180. Escrow showed 60 B earned, 40 B paid and 20 B reserved. | `0x3797cf62e4b1d7eac6f066dc419241038b8a38b2ff4deea40f5d891f381d3012` |
| 28 | 2180 | Mock operator blocked only transfers of B from escrow to the fixed manager. | `0x03a4ba95cacf0e91b3c4f1293f1632bc610a6d4db2224ca3a97e5a1de763b468` |
| 29 | 2180 | **Reverted.** The 20 B claim reached the blocked token transfer. | `0xe20d347170c71b68521fb09f9f87f90b25d3327afe54363ff567e20e4e1c9a8f` |
| 30 | 2180 | Treasury terminated. Q froze at 180. Escrow held 60 B, of which 40 B became refundable. | `0x6cfaa316dd3924582a2c93849d503c7c5926583fb0f01d791ffa5006b03072d6` |
| 31 | 2181 | **Reverted.** The manager tried to remove one quarter of the position after authority ended. | `0x75492086dcaaf48e39310d9ff8b91c511ee14bd69cefe671bc1f872e519f34fb` |
| 32 | 2182 | Treasury removed all liquidity. Core returned 698.218788 A and 498.228754 B principal plus 0.301038 A in LP fees to the vault. | `0x649d044e6d2a92611517b13d7bd15a1de052c59994d895df67c51e4045805333` |
| 33 | 2183 | Including idle inventory, treasury received 2,100.346049 A and 1,900.054977 B. Vault balances and owned liquidity were zero. | `0x47a4e9753944da6a838a331c601add06c54aedbb6b321a313a3796ff2353a25d` |
| 34 | 2184 | Treasury received the 40 B refund. Escrow retained exactly 20 B. | `0xb0003969a46981418c41241d6ace2f32310fae8efa33958f35abd1fd95f18185` |
| 35 | 2185 | Mock operator restored the manager route. | `0xdf05cf2d82b88b4e8ccacc00b5e127419c0dde77a94e7ae2efe61438fb28cabd` |
| 36 | 2186 | Manager received the preserved 20 B. Final manager receipts totaled 60 B. | `0x33e868e18fa94271636a2c9280ad173eeefc6d383c2bd7ef2e685946741d060d` |
| 37 | 2187 | Repeated manager claim succeeded with zero transferred. | `0xa32e761bb134db7ce41f0430ff955414927b3c360700cc07f5391e9d74e1fb89` |
| 38 | 2188 | Repeated treasury refund succeeded with zero transferred. Escrow held zero. | `0x370888a76f2cfcd031cd11640867bf383a96c5a7d684978e9fb03ce690a407cf` |

Anvil permits the same timestamp across distinct blocks. The Q=120 claim and the Q=180 fault/claim/termination sequence use this feature deliberately. The blocked claim returned `TransferFailed(address)` for the actual B token. Its nested call trace contained the escrow's `transfer(manager, 20000000)` and the mock's `blocked route` error. Before the revoked removal, the controller simulated the identical manager, calldata, live position and bounds at active block 29. It succeeded there and reverted with `InvalidPeriod()` at block 31, inside the same validity window. Both mined failures left the recorded position, entitlement, treasury, manager, vault and escrow token balances unchanged. Transaction gas is outside these mock-token balances. [Worked compensation fixture](COMPENSATION.md)

### Interrupt and recover on a separate run

At the bottom of the page expand **Disposable run management**, enter the full ID of the current run and select **Reset named run**. Wait for the page to show a different funded run ID and select **Use this demo run** again. Activate, choose the alternate interruption action, return to the opening band and close the recovered position. The replay used `0x8915e6311994f8eac80556561ce392859a164c9977f23bf99e866267e7255b7c`. Its funded anchor changed even though both runs reached the same height on chain 31337.

| Block | Action and service observation | Transaction hash |
| ---: | --- | --- |
| 23 | Treasury activated at 2000. | `0x3939b4609afd7d883b20121b69be3fa1ed1e26fc512cdeee05296f2102235da3` |
| 25 | At +90 s the trader offered 700 B toward tick 120. Actual tick 120 was outside the half-open position. Q=90. | `0x75aa56c65590b6645828cff03d166904fd0f6c2374fc571e91e3c31434b8c8d9` |
| 26 | At +210 s the trader offered 700 A toward tick 0. Actual tick −1 qualified again. Q remained 90. | `0x102dea496774c5f0cafba14cdd44ebeef1ad02da79f37372327b6267e8acd1cb` |
| 27 | Treasury terminated at +240 s with Q=120. Independent IPC inspection found 40 B earned and reserved, 60 B refundable, and 100 B in escrow. | `0x6a1945f83bf29900d7ce6f48ae3714612e5565633c63ff14153932b1a68f2b49` |

### Permitted manager rerange on a fresh run

Use an accepted, funded run from the updated launcher. Select **Use this demo run**, activate, then select **Manager journey: checkpoint the seed after 30 s**. Follow the manager, trader and treasury actions below. After withdrawal select **Build statement** and **Download JSON**. To exercise the path while keeping another deployment running, serve the built frontend as above and run the following command.

```bash
timeout 120s python3 -Bu scripts/viewer/check_statement.py manager
```

This command creates a fresh disposable chain, verifies its funded anchor and contracts, drives the actual page in Chromium and closes only its test fixture. Set `CHROMIUM_PATH` to an installed compatible Chromium if needed. The existing payment and interruption paths are separate choices after activation. [Browser journey](../viewer/check-manager.mjs) · [Core and custody checks](../scripts/viewer/check_manager.py)

The manager requests exactly 100,000,000,000 L at [−180, 180). Its width is 360 ticks, both edges align to spacing 60, and each extends the opening band by 60 ticks. C1 allows width 480 and extension 120. Execution requires a stored tick in [0, 1), an inclusive window of [2030, 2040] s, a maximum add input of 900 A and 900 B, and minimum removal principal of 598 A and 598 B. The controller checks the old ID, reads both candidate core keys and simulates the complete call from the named manager against actual parity inventory. It then submits the same calldata at 2031. No token, time, actor or range can be selected in the browser.

The verified run ID was `0x7416c778cee864418d1141605914ffcc16058ad6241bbfdf13a73f80a307f8f9`. The pool was `0xfa42b6fad8a05b808efa84076e1a2bb57fb52c889451eaed5c34c84100143ac7`, the core `0xeA65a3402Cb39E04Da646933985B1c9670d0e23c`, the vault `0xEE1Ec117328B89cB4ba89E5CA28C7Ef30A9b0D15`, and the manager `0x27b5fa6358b7bfa95D5eD5900b71fB2c0C120E7f`. The mined calldata bound terms hash `0x23628b6ca79fdf9a27d29082238ddd56df65bed2962af104ee8e463926023ebc` and the vault seed ID `0x77ee59b1b9a818bb00e2a2e2509a895707880844bb62905bba88c7c3290aa9a8`. The new ID was `0x8fe15812f7e8549f69e645608e08433732fe8f7059cecca65f548e7d72e2e8f6`. Each ID binds the pool, vault owner, ticks and salt.

| Block | Time | Actor and observed result | Local transaction hash |
| ---: | ---: | --- | --- |
| 23 | 2000 | Treasury activated the parity seed, salt 1, [−120, 120). | `0x1fdfc1daaadcb4156ceeedd9d6db6270c3ce352068a3c25c4e62c2a6741d06f7` |
| 25 | 2030 | Treasury checkpointed Q=30. The idle vault held 1,401.826223 of each token. | `0xc5704a15af016bd0728b534fa79405a3b6680e887cd45d7f81b413cf76bc7653` |
| 26 | 2031 | Manager atomically retired salt 1 and installed salt 2. Q=31 and lastAdjustment=2031. | `0x79b5055eee91042c28237550b543363359eaf5c5aa29f84948f2625bd625af0f` |
| 27 | 2090 | Trader offered 700 B for A to tick 120. The fill used 603.584180 B for 598.173776 A, leaving 96.415820 B unspent. Stored tick 120 qualified. Q=90. | `0x11021c16c1678abff86c5728e33a12ad5493b1462b2a007b7e120c28c5dc50f2` |
| 28 | 2180 | Treasury terminated at Q=180. Escrow held 100 B. | `0xc3e1b98b9d3501772a45efc6e15ca1c054753330d0cb07356cc6c07337204d0b` |
| 29 | 2182 | Treasury removed all vault liquidity and collected LP fees. | `0xdfd20568e498032ab1ef86dc35563ff1c90416db9d02eb0bc3fadb90f4af2548` |
| 30 | 2183 | Treasury withdrew both idle balances. The vault held zero A and zero B. | `0x186a834870edce478c68cea60a96a713f72c5aea1b0f9be806190f4d2554ad70` |

The removal returned 598.173776 A and 598.173776 B. The replacement consumed 895.917529 A and 895.917529 B. Both legs had zero fees, leaving 1,104.082470 of each asset idle. The test independently calculated rounded principal from the two boundary prices and read both core keys before and after. Vault-owned L moved from 100,000,000,000 to zero on salt 1 and from zero to 100,000,000,000 on salt 2. All four core liquidity changes in this pool were counted in log order from funding through exit. At most one vault identity held liquidity. After the adjustment the next eligible time was 2061. An otherwise-valid read-only removal simulation at 2031 returned `AdjustmentCooldown()`. A fresh valid window succeeded in simulation at 2090.

Tick 120 is outside the half-open opening band and inside the installed position. The extension still covers the entire agreed band. Under C1 this position continued earning. The downloaded statement covered blocks 15–30 and 19 product events, including both rerange legs and their salts. Persisted qualifying intervals were 30, 1, 59 and 90 seconds. The two checkpoints in the rerange transaction both recorded Q=31. The final 180 s over the original 300 s earned 60 B. The reserve and claimable amount were 60 B, the treasury could refund 40 B, and neither party had pulled compensation.

At exit the vault received 297.743752 A and 1,497.690955 B principal, plus 1.810752 B in LP fees. Including idle assets the treasury actually received 1,401.826222 A and 2,603.584177 B. Escrow held its original 100 B throughout. The browser, statement, token balances, core fee growth and mined receipts agreed. The browser showed pending, mined and stale-position error states. Wrong run, stage, Host, Origin, CSRF token and extra fields were rejected. Two concurrent identical rerange requests produced one successful receipt. Page load and download left the head unchanged. This author replay measures C1 service delivery. The matched-retainer results and buyer-specific economic questions remain as recorded in M6.

### Control boundary and browser replay

The four read RPC methods are `eth_chainId`, `eth_call`, `eth_getCode` and `eth_getBlockByNumber`. The separate action endpoint accepts the current run ID, stage version and an allowlisted action name. The rerange action also requires the seed position ID displayed in the current snapshot. This field is an identity check. The controller computes the authorized target and calldata independently. Each action fixes the actor, contract, calldata and timestamp inside the launcher. The reset endpoint accepts only the run, version and exact typed ID. Both require the literal loopback Host, exact frontend Origin, JSON and the per-run anti-CSRF header. A nonblocking lock serializes writes. Under that lock the controller checks the funded anchor, agreement marker, chain, current head, lifecycle, roles, terms and runtime bindings over owned IPC. Receipt reconciliation precedes the next step. An uncertain submission blocks retries. The pinned Anvil also listens on an ephemeral loopback port with CORS disabled. The application uses the restricted gateway and assumes a trusted local machine. [Controller](../scripts/viewer/journey.py)

With the built frontend and a fresh funded fixture running, use the installed Playwright browser or set `CHROMIUM_PATH` to your installed compatible Chromium. Use the following commands in the same verification shell.

```bash
python3 -B scripts/viewer/artifacts.py --check
npm --prefix viewer run build
node viewer/check-browser.mjs funded
node viewer/check-browser.mjs faults
read -r -p 'Full funded demo run ID to replay and reset: ' demo_run_id
timeout 240s node viewer/check-journey.mjs "$demo_run_id"
```

The journey checker drives the actual page, compares each transaction hash, block time, sender and target against the mined block, and separately reads token balances and escrow rights at that block. The receipt status and revert trace come from the launcher's IPC. The checks cover denied Host/Origin, invalid session credentials, wrong stage or run, extra target fields, unavailable RPC methods, concurrent duplicate activation, replay, transport failure and a stale manifest after reset. Page load and refresh left the funded head unchanged. No uncaught page errors occurred on the completed journey. The narrow-screen layout passed at 390 px. [Browser checker](../viewer/check-journey.mjs)

During development, a browser assertion read the old manifest immediately after pressing reset. The old and newly fetched IDs were equal and the process exited 1 after the successful zero-value retries. The checker now waits up to 45 seconds for a different verified ID to render on the page, confirms the old controls have cleared, then verifies the new manifest and rejects the old credentials. A full replay exited 0. On subsequent failures, stderr includes the action, observed run, head, last receipt and available page/transport errors. An intentional stale-ID invocation exercised that diagnostic at block 27 before any action.

## Agreement statement and JSON export

In **Agreement statement**, select **Build statement**. The section shows the coverage, accepted revision, opening observation and band, service intervals, settlement, token movements and known demo failures. Expand **Ordered product events** for arguments and transaction references. **Download JSON** saves the reconciled statement for the displayed block. A new block or run clears the previous report. A stale snapshot disables download. Building and downloading are read-only. Launchers started before this feature need the updated launcher for the statement route.

The gateway accepts a single evidence request, `GET /statement/<run-id>/<decimal-block>/<block-hash>`. It reads only its verified deployment over owned IPC. The browser's four-method RPC and fixed action allowlist retain their original scope. The collector locates the vault's first code block at or before the funded anchor, verifies the creation receipt and checks block ancestry through the requested hash. It queries the vault, escrow and hook in eight-block windows and compares the ordered results, including topics and data, with receipts from every transaction in those blocks. Limits are 128 blocks, eight transactions per block and 1,024 product events. An unsupported range fails explicitly. [Collector](../scripts/viewer/statement.py)

The export schema is `unison.c1.statement.v1`. It includes the run marker, chain, endpoint, build, terms and hash, all contract addresses, token decimals, block hashes and timestamps, ordered decoded events, signed vault movements, fixed-recipient transfers, as-of custody, obligations and same-block contract reads. Integer quantities and indices are decimal strings. Each interval identifies its originating checkpoint and, if persisted, its ending checkpoint. The collector credits elapsed seconds using the *previous* qualification and checks the cumulative total emitted by the hook. It labels any uncheckpointed tail projected and clips it at the effective stop. Entitlement uses the original duration and a single cumulative floor.

The mock tokens emit no ERC-20 transfer logs. For a financial event the collector checks both sides against historical balance changes in its single-transaction block. An ambiguous multi-transaction transfer block fails reconciliation. Core principal and LP fees enter the vault first. The treasury withdrawal includes idle inventory and those proceeds. Adding the two receipts would count the same assets twice. Known failed demo calls appear separately with their status-zero receipt, hash, and journal-sourced revert data. Zero-value retries can succeed without emitting a product event.

### Checked browser downloads

Build the page and run its loopback preview as above. The check reuses the pinned artifacts and installed Chromium. Set `CHROMIUM_PATH` if the browser is outside Playwright's default location. From the repository root run

```bash
python3 -B scripts/viewer/artifacts.py --check
npm --prefix viewer run build
timeout 240s python3 -Bu scripts/viewer/check_statement.py payment swap expiry
```

The test creates owned, isolated fixtures. It routes the browser's normal gateway origin to a test loopback listener running the actual reader, so an existing demo can stay at its current block. For expiry only, the test explicitly mines an empty observation block at 2307 seconds on its own chain. No browser time control is added. To keep downloaded files, set `STATEMENT_DOWNLOAD_DIR` to an existing directory outside the repository. [Fixture driver](../scripts/viewer/check_statement.py) · [Browser assertions](../viewer/check-statement.mjs)

| Downloaded state | Range / product events | Persisted / projected Q | Earned / paid / reserved | Refunded / refundable |
| --- | --- | ---: | ---: | ---: |
| Funded | 15–22 / 5 | 0 / 0 | 0 / 0 / 0 B | 0 / 0 B |
| Active at +1 s | 15–24 / 8 | 0 / 1 | 0.333333 / 0 / 0.333333 B | 0 / 0 B |
| Terminated with payment blocked | 15–30 / 14 | 180 / 180 | 60 / 40 / 20 B | 0 / 40 B |
| Treasury refunded | 15–34 / 18 | 180 / 180 | 60 / 40 / 20 B | 40 / 0 B |
| Manager paid after restoration | 15–38 / 19 | 180 / 180 | 60 / 60 / 0 B | 40 / 0 B |
| Interrupted then recovered | 15–27 / 12 | 120 / 120 | 40 / 0 / 40 B | 0 / 60 B |
| Effective expiry without finalization | 15–25 / 8 | 0 / 300 | 100 / 0 / 100 B | 0 / 0 B |

Both acceptances and escrow credit were present before or at funded block 22. The final closeout download separated 698.218788 A and 498.228754 B in removed principal, plus 0.301038 A in LP fees, from actual treasury withdrawals of 2,100.346049 A and 1,900.054977 B. It reported both known mined failures. The interrupted position earned 90 s, spent 120 s outside range, then earned another 30 s. The unfinalized expiry export capped the open interval at 2300 and showed no close event.

Each download matched the displayed block and independent viem reads of Q, escrow rights and the actual escrow token balance. The tests rejected missing, duplicate and unordered logs, stale run identity, unknown schema/build, altered earnings and transport failure. Building and saving left the chain head unchanged. A further read-only browser download from the earlier swap run `0x8915e6311994f8eac80556561ce392859a164c9977f23bf99e866267e7255b7c` agreed at block 27, hash `0xf22c6de0c4dd85831e3855adb5d7f811ca15b16f853036a37a75f962185c439a`.

The provider supplies logs, receipts, block headers and historical state. Cross-checks detect inconsistent responses and many omissions. They cannot establish completeness against a provider that consistently withholds evidence. Checkpoints emit qualification, tick and liquidity, but omit the full historical reason bitmask. Failure coverage extends only to the available demo journal. Service pay measures agreed position conditions. M6 found matching liquidity delivery under the bounded retainer, and buyer-specific economic justification remains open.

## Read-only verification

The real browser check uses Playwright Core 1.55.1. Supply an installed compatible Chromium through `CHROMIUM_PATH`, or prepare Playwright's local browser with `viewer/node_modules/.bin/playwright-core install chromium --only-shell`. A slow download can be resumed from the same [Microsoft-hosted build 1193 archive](https://playwright.download.prss.microsoft.com/dbazure/download/playwright/builds/chromium/1193/chromium-headless-shell-linux.zip). On Linux x86-64 the rehearsed archive was 109,413,936 bytes with SHA-256 `7d93c385edba3ac9f10f13037e600353f29f84691f09d26b935bfc117bbceb98`. Verify the digest, extract outside the repository and set `CHROMIUM_PATH` to the extracted `chrome-linux/headless_shell` executable. The checks below assume the fixture and frontend are running. Each browser invocation reads the current state. Issue the indicated commands in the separate fixture terminal.

```bash
node viewer/check-browser.mjs funded
# Fixture: activate
node viewer/check-browser.mjs active
# Fixture: interrupt
node viewer/check-browser.mjs interrupted
# Fixture: terminate
node viewer/check-browser.mjs terminal
node viewer/check-browser.mjs faults
# Save the public manifest outside Git before resetting this exact run.
viewer_old_manifest=$(mktemp)
curl -fsS http://127.0.0.1:18547/deployment.json -o "$viewer_old_manifest"
# Fixture: reset <full-current-run-id>; wait for Ready.
node viewer/check-browser.mjs old-manifest "$viewer_old_manifest"
node viewer/check-browser.mjs funded
```

| Actual fixture state | Block / core tick / owned L | Persisted / projected seconds | Earned = reserved = claimable | Refundable |
| --- | --- | --- | ---: | ---: |
| Funded | 22 / 0 / 0 | 0 / 0 | 0 B | 0 B |
| Qualifying | 24 / 0 / 100,000,000,000 | 0 / 1 | 0.333333 B | 0 B |
| Interrupted | 25 / 120 / 100,000,000,000 | 90 / 90 | 30 B | 0 B |
| Terminated after interruption | 26 / 120 / 100,000,000,000 | 90 / 90 | 30 B | 70 B |

The funded vault held 2,000 A and 2,000 B. After seeding it held 1,401.826223 of each. Escrow held 0 A and 100 B across these stages. Claims and refunds transferred zero during this viewing exercise. Hook failure bits at interruption were 128 (tick outside). At termination they were 130 (also stopped). The browser assertions compare these values with the page, verify a common block for every code/contract read, check the console and check narrow-screen overflow. Fault cases use browser-local response interception. The stale-manifest check uses a real second deployment on the same chain ID.

React, React DOM, viem, Vite and the React type packages declare MIT licenses. TypeScript and Playwright Core declare Apache-2.0. The lockfile also includes transitive ISC and BSD-3-Clause packages. Dependency packages carry their license texts. Product, fixture and upstream Solidity retain their existing notices. [Dependency lock](../viewer/package-lock.json) · [Upstream attribution](../experiments/m1/README.md#attribution-and-license-scope)

The permitted manager path has an author browser replay. A6 still needs another developer to reproduce the pinned setup and rehearse the full demonstration across fresh runs. The local receipt list lives only for its run. The M6 matched retainer delivered identical tested liquidity. Customer acceptance and economic justification remain open.
