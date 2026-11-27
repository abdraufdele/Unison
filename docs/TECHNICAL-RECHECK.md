# Local technical recheck — 25 November 2026

Scope: an author-side technical recheck of the implemented local MVP, not an independent A6 review, audit or customer validation. Product source and tests are unchanged from `bda7acf9af77a5406a82a1d8e7af920a657c890f`. This change removes ripgrep from the mutation runners and corrects stale workflow statements. Use the commit containing this record for those runner fixes; the older pinned reviewer revision does not contain them.

## Executed checks

- Root Foundry suite: 115 passed, 0 failed, 0 skipped across 12 suites, using native Solidity 0.8.26, pinned Foundry 1.8.7, Cancun, via IR and optimizer 200.
- Native Linux Node 22.19.0: TypeScript checking and Vite production build passed. The compiled viewer ABI/source identity check passed.
- M6 published-data checker: 21 lifecycles, 45 orders and 150 receipt rows reconciled. This rechecked the published comparison data; it did not regenerate all three-arm workloads.
- The five preserved M1 import hashes matched. This did not rerun the separate historical M1 suite.
- Browser: Playwright Core 1.55.1 with Chromium headless shell build 1193, against the built viewer and newly deployed actual product contracts on owned disposable Anvil chains. All eight JSON exports reconciled with block-pinned contract reads: funded, active, termination, refund, repeated refund, swap interruption, expiry and manager rerange. Missing, duplicate and out-of-order event responses were rejected. Browser statement checks also exercise invalid schema/build/run/amount and unavailable-response rejection.
- The separate browser journey passed: actual payment failure and recovery, independent principal receipt, swap interruption/return, receipt identities and independent balances, duplicate/stale request rejection, identity/origin/control restrictions, reset and read-only checks. No page error failed the browser assertions. The local reader logged three broken pipes during aborted requests; the journey completed with exit 0. These are request-disconnect diagnostics, not evidence of additional contract failures.

The principal financial paths reproduced 180 qualifying seconds / 60 B earned, 40 B previously paid, 20 B reserved and 40 B refundable; the swap interruption path earned 40 B for 120 seconds; expiry earned 100 B for 300 seconds. Manager reranging was a separate fresh run. These are six-decimal mock tokens, not actual USDC.

## Mutation replay

Each runner requires baseline success, successful mutant compilation, then the exact intended failing assertion. The test files stay unchanged in the isolated copies. A mutant test exit of 1 is the desired outcome; the replay runner must exit 0. The scripts now use GNU grep, avoiding an undeclared ripgrep prerequisite.

All four runners exited 0. Every baseline and mutant build exited 0; each deliberately broken implementation then failed the unchanged selected test with exit 1:

- Omitted old-state checkpoint: `OldIntervalLost(100, 0)`.
- Refund steals an earned unpaid reserve: `ReserveStolen(20000000, 0)` (Forge also prints unit annotations).
- Manager removes the expired position: `ExpiredPositionChanged(100000000000, 0)`; the trace contains the unauthorized zero-liquidity adjustment.
- Principal exit calls the blocked manager claim: `PrincipalReceiptShort(1900054977, 1401826223)`; the exit subtree contains the failed escrow claim and transfer.

These demonstrate that the selected regression tests detect these four specific violations. They do not prove absence of other defects.

## Reproduce

Use the pinned dependency/toolchain setup in [README](../README.md#setup) and [viewer runbook](LOCAL-VIEWER.md). Activate native Linux Node and Foundry before running; `node`, `npm`, `forge` and `anvil` must resolve to Linux tools. The initial verification wrapper needed its Vite root set to `viewer` and Foundry added to PATH; those launcher mistakes were corrected before collecting successful browser results.

```bash
forge test --offline --use "$HOME/.svm/0.8.26/solc-0.8.26" -vv
(cd experiments/m1 && sha256sum -c SHA256SUMS)
python3 -B experiments/m6/check.py
python3 -B scripts/viewer/artifacts.py --check
npm --prefix viewer run build
bash scripts/check_service_clock_mutation.sh
bash scripts/check_reserve_mutation.sh
bash scripts/check_closeout_mutation.sh revocation
bash scripts/check_closeout_mutation.sh payment
```

Install the browser pinned by the existing Playwright package if it is absent; this recheck stored it only under ignored `.local/verification/browsers`:

```bash
PLAYWRIGHT_BROWSERS_PATH="$PWD/.local/verification/browsers"   viewer/node_modules/.bin/playwright-core install chromium --only-shell
export CHROMIUM_PATH="$PWD/.local/verification/browsers/chromium_headless_shell-1193/chrome-linux/headless_shell"
```

With built preview running on loopback port 5173, run `python3 -Bu scripts/viewer/check_statement.py`. That checker owns isolated test chains and a temporary reader port. For the additional full journey, start a fresh funded demo launcher, then run `node viewer/check-journey.mjs <full-current-funded-run-id>`. This command intentionally changes and resets only that named disposable run. Stop the launcher and preview afterward. Raw logs, downloaded browser and temporary wrappers remain ignored; no credentials or machine-specific logs are published.

## Remaining limits

This recheck establishes observed local technical behavior only. The browser begins after launcher-side acceptance/funding and uses fixed actors; general wallet onboarding is not implemented. Anvil and a mock opening reference do not establish public-network/oracle compatibility. A shared RPC provider cannot independently guarantee complete chain history. No production deployment, audit, customer acceptance, buyer-specific economic advantage, independent A6 reproduction, final human-timed video or submission is established by this record. The matched managers delivered identical service in M6; a refund alone does not create joint economic value. See [comparison](M6-COMPARISON.md) and [independent checklist](A6-REVIEWER.md).
