# Local agreement viewer

The viewer reads a single mock C1 agreement at one mined block. It opens in the accepted and fully funded state. The service clock shows the contract's projected entitlement at the displayed block alongside the last persisted checkpoint. Refreshing the page only reads data. [M6 comparison and economic limits](M6-COMPARISON.md)

## Start, inspect and stop

Use the [pinned root setup](../README.md#setup), the pinned core checkout and the existing M6 Python environment (Python 3.12, Web3.py 7.13.0). The checked tools were Anvil/Forge 1.8.7, Node 22.19.0 and npm 11.21.3. From the repository root, use the first command when the Forge artifacts are missing or their source inputs changed.

```bash
forge build --offline --use ~/.svm/0.8.26/solc-0.8.26 experiments/m6/Comparison.sol test/fixtures/CustodyFixture.sol test/fixtures/MockOpeningReferenceAdapter.sol experiments/m1/vendor/v4-core/src/PoolManager.sol
python3 -B scripts/viewer/artifacts.py --check
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

The browser accepts only this build and endpoint. It verifies the funded block anchor, code, vault marker, terms bindings and recipients, pins financial/core calls to the same block and rechecks that block hash. Changing the manifest clears the previous snapshot. Read failures mark retained same-run data stale. Identity or missing-code failures clear the financial display. The local gateway exposes four read RPC methods. Fixture transactions and time controls use the launcher's owned IPC connection. The browser receives public data only. [Reader](../viewer/src/read.ts) · [Fixture launcher](../scripts/viewer/demo.py)

## Verification

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

Further M7 work includes a reconstructible event-based statement/export and tested user actions. A6 needs the full independent fresh-run demonstration, including failed compensation and principal exit. The M6 matched retainer delivered identical tested liquidity. Customer acceptance and economic justification remain open.
