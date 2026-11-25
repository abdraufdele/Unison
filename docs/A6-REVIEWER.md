# A6 independent developer checklist

**Target revision** `a3c5173d9546d017ba322b66ea8096eabdd8ba55` in the public Unison development history. Keep this checklist and its linked setup instructions open while testing that revision in your own clean checkout. Record your fresh runs and observations. A6 remains pending until a second developer supplies a dated record. [Local runbook](LOCAL-VIEWER.md) · [Earlier author rehearsal](A6-AUTHOR-REHEARSAL.md) · [Dependency revision and revalidation](VIEWER-DEPENDENCIES.md)

## Prepare and start

1. Use Linux x86-64 or WSL2 with Git, Bash, Python 3.12 with Web3.py 7.13.0, Forge and Anvil 1.8.7 at `985eeea031d79922cd654d4e94e6c3701e1c7d73`, native solc 0.8.26, Node 22.19.0 and npm 11.21.3. The viewer lockfile selects Playwright Core 1.55.1 and its Chromium headless shell build 1193. Record which tools, caches and libraries were already present.
2. Clone into a new directory. Run the following from the directory that will contain the checkout.

   ```bash
   git clone --branch development --single-branch https://github.com/abdraufdele/Unison.git unison-a6
   cd unison-a6
   git switch --detach a3c5173d9546d017ba322b66ea8096eabdd8ba55
   git rev-parse HEAD
   git status --short
   ```

3. Verify the five M1 hashes, compiler hash, v4-core commit, Solmate gitlink and clean dependency trees. Use the pinned [dependency setup](../experiments/m1/REPLAY.md#tools-and-inputs) or the equivalent shallow fetch in the [viewer runbook](LOCAL-VIEWER.md#start-inspect-and-stop). Build from sources with the viewer's explicit four-input Forge command. Run `python3 -B scripts/viewer/artifacts.py --check`, `npm --prefix viewer ci` and `npm --prefix viewer run build`. For automated browser checks, use the lockfile-selected shell installed with `viewer/node_modules/.bin/playwright-core install chromium --only-shell` or set `CHROMIUM_PATH` to its executable.
4. Use a disposable local environment with loopback ports 18547 and 5173 free. From the checkout root start `python3 -Bu scripts/viewer/demo.py` in one foreground terminal. Wait for **Ready**, record the run ID and verify the manifest at `http://127.0.0.1:18547/deployment.json`. In another terminal run `npm --prefix viewer run preview` and open `http://127.0.0.1:5173/`. An occupied port requires a different disposable environment or network namespace. Leave its owner running.

## Complete two rounds

In each round run all three rows on distinct funded identities. On the funded page check block 22, 2,000 A and 2,000 B in the vault, and 100 B in escrow. Refresh, build a statement and download it. Verify the head hash stays fixed. Select **Use this demo run**. After each click wait for the mined receipt and refreshed block. Save final statements and your own receipt references outside Git.

| Path from funded state | Observations to verify |
| --- | --- |
| Activate → manager checkpoint → extend → offer 700 B → terminate → remove → withdraw | Old salt 1 retires and salt 2 holds 100,000,000,000 L in [−180, 180). At tick 120 the fixed opening band stays [−120, 120) and service qualifies. Final Q=180, earned/reserved 60 B, paid/refunded 0, refundable 40 B. Treasury receives 1,401.826222 A and 2,603.584177 B. |
| Activate → interrupt → return → close recovered position | Tick 120 interrupts at Q=90. Tick −1 qualifies again with Q still 90. At close Q=120, earned/reserved 40 B, refundable 60 B. Principal is still invested and neither recipient has pulled a payment. |
| Activate → trade inside range → claim 40 B → checkpoint → block manager route → attempt claim → terminate → attempt revoked removal → remove → withdraw → refund → restore → claim 20 B → repeat claim and refund | Expand both reverted receipts. Check `TransferFailed(address)` for the mock B route and `InvalidPeriod()` for the previously valid removal. At termination Q=180, earned 60 B, paid 40 B, reserved 20 B and refundable 40 B. After refund escrow retains 20 B. Final manager receipts total 60 B and treasury refund is 40 B. Repeats transfer zero. Treasury receives 2,100.346049 A and 1,900.054977 B in principal, fees and idle inventory separately from the refund. |

Before leaving each path, inspect its statement's run ID, terms, funded anchor, as-of hash, intervals, movements, obligations and failure receipts. Compare `derived` with `contractReads`. Record actual transfer quantities and fees, and distinguish vault receipts from treasury withdrawals. Keep the statement after termination and after refund in the payment-failure path as well.

Between paths and rounds open **Disposable run management**, type the exact current ID and choose **Reset named run**. Wait for a new onchain ID and funded anchor. Five such resets produce six identities. Old controls must clear. Verify that the prior manifest clears the controls and both the old token and old run ID fail to authorize an action. If you did not check these denials during the five resets, use one additional named fresh funded run for the automated [browser replay](LOCAL-VIEWER.md#control-boundary-and-browser-replay). Run `node viewer/check-journey.mjs FULL_FUNDED_RUN_ID` with the ID printed by your own launcher. This check drives the payment and interruption paths and performs a named reset. At finish type `stop` in your launcher terminal and Ctrl-C in your preview terminal.

Compare both rounds' Q, paid, reserved, refunded, refundable, idle and withdrawn amounts, LP fees and interval durations. Addresses, run IDs, terms hashes and receipt/block hashes can change. Record any gas differences independently of token outcomes. A missing/reordered event, unexpected receipt or error selector, balance mismatch, wrong fee recipient, stale action accepted, head movement on load/download or unexplained deterministic difference is a failed or incomplete rehearsal. Record the first failing step with its run and block. Keep objections even when the assertions pass.

## Reviewer record

| Field | Actual reviewer entry |
| --- | --- |
| Reviewer, role and date with time zone | |
| Checkout revision, OS/kernel, tool and browser versions | |
| Pre-existing tools/caches, source and dependency pin checks | |
| Setup deviations, first error, remedy and steps rerun | |
| Round 1 and round 2 run IDs, funded anchors and as-of hashes per path | |
| Receipt references, error selectors and downloaded statement locations | |
| Measured Q, rights, principal, fees and final custody per run | |
| Deterministic comparison, stale-run checks and read-only head checks | |
| Result, missing evidence, objections and follow-up | |
