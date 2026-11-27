# A6 independent developer checklist

**Implementation and reviewer target** `e14fb19801c9c3bede31b36d9cfeb2ad237c66f2` on development. Keep these current instructions open alongside the detached checkout. The earlier checklist targeted `5b821b93c8cc5480e74a38e4afba66683fd0fca2`. The published two-round author receipts belong to their original checkout. A6 requires a second developer’s dated results from two fresh rounds on the current target. [Implementation tree](https://github.com/abdraufdele/Unison/tree/e14fb19801c9c3bede31b36d9cfeb2ad237c66f2) · [Historical author rehearsal](A6-AUTHOR-REHEARSAL.md) · [Current author verification](DEVELOPMENT-EVIDENCE.md)

## Prepare and start

1. Use Linux x86-64 or WSL2 with Git, Bash, Python 3.12 with Web3.py 7.13.0, Forge, Cast and Anvil 1.8.7 at `985eeea031d79922cd654d4e94e6c3701e1c7d73`, native solc 0.8.26, Node 22.19.0 and npm 11.21.3. The viewer lockfile selects Playwright Core 1.55.1 and its Chromium headless shell build 1193. Record which tools, caches and libraries were already present.
2. Clone into a new directory. Run the following from the directory that will contain the checkout.

   ```bash
   git clone --branch development --single-branch https://github.com/abdraufdele/Unison.git unison-a6
   cd unison-a6
   git switch --detach e14fb19801c9c3bede31b36d9cfeb2ad237c66f2
   git rev-parse HEAD
   git status --short
   ```

3. For the historical `e14fb19` target, read that checkout's own README dependency block (`git show HEAD:README.md`); its vendor-based setup predates the root `lib/` migration. For a later layout revision, use its own submodule setup and record the exact revised target rather than mixing revisions. On a provisioned host run `make prerequisites`, then `make viewer-install` for the locked packages. Run `make deps fmt-check sizes`, `make test SEED=0x19112026` and `make artifacts viewer-build`. Record executed results. The current suites live in [unit](../test/unit/), [integration](../test/integration/), [fuzz](../test/fuzz/) and [invariant](../test/invariant/). The four isolated faults have their own `make mutations` target. For automated browser replay, set `CHROMIUM_PATH` to the compatible headless shell. [Operator runbook](OPERATIONS.md)
4. On loopback with ports 18547 and 5173 free, run `make demo` in one terminal. Wait for **Ready**, record its run ID and verify the manifest at `http://127.0.0.1:18547/deployment.json`. Run `make viewer-preview` in a second terminal and open `http://127.0.0.1:5173/`. The six-decimal assets and opening reference are mocks. The fixed demo roles use accelerated local chain time.

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
