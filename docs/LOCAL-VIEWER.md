# Local agreement viewer

The viewer reads a single mock C1 agreement at one mined block. It opens in the accepted and fully funded state. The service clock shows the contract's projected entitlement at the displayed block alongside the last persisted checkpoint. Page load, polling and **Refresh reads** leave the chain at the same head. Select **Use this demo run** to operate the named local actors. [M6 comparison and economic limits](M6-COMPARISON.md)

## Start, inspect and stop

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

### Control boundary and browser replay

The four read RPC methods are `eth_chainId`, `eth_call`, `eth_getCode` and `eth_getBlockByNumber`. The separate action endpoint accepts only the current run ID, stage version and an allowlisted action name. Each action fixes the actor, contract, calldata and timestamp inside the launcher. The reset endpoint accepts only the run, version and exact typed ID. Both require the literal loopback Host, exact frontend Origin, JSON and the per-run anti-CSRF header. A nonblocking lock serializes writes. Under that lock the controller checks the funded anchor, agreement marker, chain, current head, lifecycle, roles, terms and runtime bindings over owned IPC. Receipt reconciliation precedes the next step. An uncertain submission blocks retries. The pinned Anvil also listens on an ephemeral loopback port with CORS disabled. The application uses the restricted gateway and assumes a trusted local machine. [Controller](../scripts/viewer/journey.py)

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

## Read-only verification

The real browser check uses Playwright Core 1.55.1. Supply an installed compatible Chromium through `CHROMIUM_PATH`, or prepare Playwright's local browser with `viewer/node_modules/.bin/playwright-core install chromium --only-shell`. The checks below assume the fixture and frontend are running. Each browser invocation reads the current state. Issue the indicated commands in the separate fixture terminal.

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

The next M7 task is a reconstructible event-based statement and export. A6 still needs independent fresh-run rehearsal, including a permitted manager action and the full demonstration. The local receipt list lives only for its run. The M6 matched retainer delivered identical tested liquidity. Customer acceptance and economic justification remain open.
