# Viewer dependency assessment · 25 November 2026

The public npm registry returned three affected **package entries** on the rehearsed lockfile at `abd7c9a`. The underlying findings were five advisories for Vite and two for ws. npm counted Vite and ws as high, and viem as moderate through its dependency on ws. The patched lockfile returned zero entries in the same full audit. Two tools also carry private bundled copies of ws outside that count.

## Findings on the rehearsed versions

Ranges and first fixes below are for the installed major version. The first five entries apply to the direct development dependency `viewer → vite@6.4.3`. Vite distributes the editor helper in its Node bundle. The last two apply to `viewer → viem@2.37.13 → ws@8.18.3`. The peer path through `viem → isows@1.0.7 → ws` resolves to the same installed package.

| Severity | Finding and applicability before the change | Affected → first fixed | Official advisory |
| --- | --- | --- | --- |
| Moderate | Windows shell expansion in editor arguments. The rehearsed Node process runs on Linux under WSL2. | Vite ≤6.4.3 → 6.4.4 | [GHSA-698v-4r3x-3vcv / CVE-2026-112943](https://github.com/advisories/GHSA-698v-4r3x-3vcv) |
| Moderate | A susceptible editor can interpret a filename as an option. WSL satisfies one prerequisite. The dev editor route also needs an attacker-influenced working directory and a susceptible editor. | Vite ≤6.4.3 → 6.4.4 | [GHSA-r825-w8mm-5pxw / CVE-2026-112944](https://github.com/advisories/GHSA-r825-w8mm-5pxw) |
| High | The editor helper's file existence check can fail on native Windows. The rehearsal used Linux filesystem and process semantics. | Vite ≤6.4.3 → 6.4.4 | [GHSA-587h-7wmj-h5pm / CVE-2026-112942](https://github.com/advisories/GHSA-587h-7wmj-h5pm) |
| Low | Cross-origin script execution requires a particular custom HTML middleware and inline module. This viewer uses the CLI's default SPA routing and an external module entry. | Vite ≤6.4.3 → 6.4.4 | [GHSA-9jrq-w75r-8gcw / CVE-2026-112945](https://github.com/advisories/GHSA-9jrq-w75r-8gcw) |
| Moderate | A dev-server import whose root-relative path matches a readable host file can expose content outside the allowed tree. The WSL host is within the affected OS class. Loopback still allows local clients. The presentation serves a built directory. | Vite ≤6.4.3 → 6.4.4 | [GHSA-rq7h-c2jc-7f22 / CVE-2026-112946](https://github.com/advisories/GHSA-rq7h-c2jc-7f22) |
| Moderate | A typed-array WebSocket close reason can disclose uninitialized memory. The viewer and its Node contract readers use fixed HTTP transport. | ws ≥8.0.0 and <8.20.1 → 8.20.1 | [GHSA-58qx-3vcg-4xpx / CVE-2026-45736](https://github.com/advisories/GHSA-58qx-3vcg-4xpx) |
| High | Peer-controlled framing can exhaust receiver memory. This requires a WebSocket receiving traffic. The demo RPC and control gateway use HTTP. | ws ≥8.0.0 and <8.21.0 → 8.21.0 | [GHSA-96hv-2xvq-fx4p / CVE-2026-48779](https://github.com/advisories/GHSA-96hv-2xvq-fx4p) |

npm reported the inherited viem range as `<=0.0.0-wagmiv2-20230628182101 || 0.2.2 - 2.49.3` and suggested viem 2.58.6. It assigned no separate viem advisory ID. A scoped npm override installs ws 8.21.0 under viem, including the deduplicated peer. The new ws receiver limits are relevant to Node WebSocket consumers. The HTTP API used by this application stays the same. [ws 8.21.0 release](https://github.com/websockets/ws/releases/tag/8.21.0)

Vite 6.4.4 fixed the five original entries, but a temporary install candidate reported a separate moderate dev-server file-deny issue specific to 6.4.4, fixed in 6.4.5. The final pin is npm's recommended same-line 6.4.6. Only the Vite and ws nodes changed in the lockfile. [GHSA-8g5g-mxqh-grgj / CVE-2026-118662](https://github.com/advisories/GHSA-8g5g-mxqh-grgj) · [Vite 6.4.6 release](https://github.com/vitejs/vite/releases/tag/v6.4.6)

## What is installed, served and exercised

- **Browser application.** The rendered production chunks contain React, React DOM, scheduler, viem, abitype, ox and the Noble curves/hashes packages. Rollup's rendered-module data showed zero contributing modules from Node ws, Vite or Playwright. The entire built directory matched the retained author-rehearsal build byte for byte.
- **Build and preview.** Vite runs as a Node tool. Both changed npm packages use the MIT license and declare no install lifecycle hooks. Vite retains its bundled notices. The existing esbuild 0.25.12 package declares a native-binary postinstall script. npm reported its existing install-script policy warning. Locked installation and the normal TypeScript/Vite build succeeded. None of the seven advisories describes an installation hook.
- **Bundled tooling exposure.** Vite 6.4.6 still bundles ws for its development HMR server, with 8.18.1 in Vite's own lock. Playwright Core 1.55.1's bundled notices and source specify ws 8.17.1. Both versions fall in the two ws ranges. npm's override cannot replace code embedded in upstream bundles. Use the built loopback **preview** for presentation and verification. Use Playwright's local Chromium launch over a pipe. HMR, remote browser connections and browser-server mode are outside the verified setup. Those modes would need separately patched tools and revalidation before use with untrusted peers. A browser/toolchain migration would change the pinned reproduction environment. [Vite upstream lock](https://github.com/vitejs/vite/blob/v6.4.6/pnpm-lock.yaml) · [Playwright bundled dependencies](https://github.com/microsoft/playwright/blob/v1.55.1/packages/playwright-core/bundles/utils/package.json)

## Revalidation

Tested dependency revision `a3c5173d9546d017ba322b66ea8096eabdd8ba55`, lockfile SHA-256 `8ab19618ed684f2354de18cf48cc7878bdc8e38ec20d529eb2dcb1a1ce229a04`. With Node 22.19.0 and npm 11.21.3, the initial sandbox DNS request failed. An authorized request to the same official registry returned the structured baseline. The final full audit returned an empty vulnerability map and exit 0. No registry or severity filters were applied.

```bash
npm --prefix viewer ci
npm --prefix viewer ls --all
npm --prefix viewer audit --json
npm --prefix viewer run build
python3 -B scripts/viewer/artifacts.py --check
```

Chromium 140.0.7339.186 drove the production preview in an isolated loopback namespace, using the existing compiled product artifacts. With the preview running, the statement command was `timeout 300s python3 -Bu scripts/viewer/check_statement.py manager payment swap`. The action replay used `timeout 240s node viewer/check-journey.mjs "$demo_run_id"` with the full ID of a fresh funded launcher run. Both exited 0. [Launcher and browser instructions](LOCAL-VIEWER.md#control-boundary-and-browser-replay)

| Browser path | Observed outcome |
| --- | --- |
| Permitted manager action | Block 26 rerange `0xe6312294429e61b73a8ec15ff637ee1252b0778685c5495d07130f4b5b47f245` moved 100,000,000,000 L to salt 2. Tick 120 still qualified. Final Q=180, earned/reserved 60 B, refundable 40 B. Treasury received 1,401.826222 A and 2,603.584177 B. |
| Interrupted service | The outward swap paused accrual at Q=90. The return to tick −1 restored qualification at Q=90. The block-27 statement reconciled Q=120, earned/reserved 40 B, refundable 60 B. |
| Failed payment and exit | Block 29 claim `0x3fde1fdebc7864c6cc429bfdfb707de255d647813688ea4877f630fd81c32a8f` reverted with the payment route blocked. After termination the manager removal also reverted. At Q=180, earned was 60 B, paid 40 B and reserved 20 B. The treasury received 2,100.346049 A and 1,900.054977 B while payment was blocked. Refunding 40 B preserved 20 B for the restored manager claim. Both retries paid zero. |

Seven JSON downloads covered manager close, swap close, funded, active, blocked-payment close, refund and final payment. Each matched the displayed as-of hash and separate contract reads. The checks rejected damaged event history, stale run/position, invalid Host/Origin/CSRF and duplicate actions. A named reset invalidated the old session. Page reads and downloads left the head unchanged. Rehearsal-owned services stopped. The historical [two-round author rehearsal](A6-AUTHOR-REHEARSAL.md) remains evidence for its original revision. Independent developer verification is still pending.
