# Submission checklist · HK-UHI11-1275

## Judge handoff

**Implementation and independent reviewer pin** `e14fb19801c9c3bede31b36d9cfeb2ad237c66f2` on development. Open the current judge documents on development and run the pinned code in a separate checkout. Main contains an earlier implementation. [Implementation tree](https://github.com/abdraufdele/Unison/tree/e14fb19801c9c3bede31b36d9cfeb2ad237c66f2) · [Judge documents](https://github.com/abdraufdele/Unison/tree/development/docs)

| Step | Where to look |
|---|---|
| Prepare the checkout | Follow the pinned clone, Python/toolchain and v4-core/Solmate setup. From the root run `make prerequisites`, `make viewer-install`, then `make deps sizes artifacts viewer-build`. [README setup](../README.md#setup) |
| Reproduce the demo | In terminal one run `make demo` and wait for **Ready**. In terminal two run `make viewer-preview`. Open `http://127.0.0.1:5173/` and confirm the funded run ID. The presentation uses six-decimal mock assets, fixed local actors and accelerated Anvil time. [Payment controls](LOCAL-VIEWER.md#run-the-payment-failure-journey) |
| Inspect in three minutes | Start with the blocked claim, treasury withdrawal and 20 B reserve after refund. Compare the separate range and swap runs, then inspect the interrupted retainer comparison and open gates. [Timed inspection route](M8-DEMO.md#three-minute-judge-inspection) · [Run-specific receipts](DEVELOPMENT-EVIDENCE.md#judge-receipt-references) |
| Check cost and scope | Both managed arms delivered equal liquidity. One interrupted period cost 9,405,402 additional gas on current bytecode. Local and Sepolia dry-runs produced simulated receipts. Owned forks exercised the official Sepolia and mainnet cores with mocks. Public deployment and explorer verification remain unexecuted. Mainnet needs a reviewed exact-transfer pair and suitable independent opening reference. [Payer totals](DEVELOPMENT-EVIDENCE.md#fresh-comparison) · [Network checks](NETWORK-CHECKS.md) |
| Complete the human work | Treasury and manager decisions on the same terms and buyer-specific cost evidence are pending. A second developer must record two A6 rounds. The presenter must time, record and check the video. An authorized submitter must verify public access, submit and retain confirmation. **Video URL and submission receipt pending.** [Independent record](A6-REVIEWER.md#reviewer-record) · [Submission checklist](#before-handing-in-the-entry) |

## Revisions a judge can inspect

All hashes below are commits in development history. The rehearsal pin, its written record and the patched runtime pin identify different artifacts.

| Artifact | Exact revision | What was checked |
| --- | --- | --- |
| Product source and M5 closeout | Product `8a1132c0475ba6a8d5c09a040a25c8065e0289fb`, closeout tests `41bf167d6e97664d98e14ece79d04ce47742b79e`, report `8ef155b5e81608dfdb7eb2324bd8eb1486b703b6` | Recorded root run passed 115 tests in 12 suites, including failure isolation and reserve protection. [Closeout](CLOSEOUT.md) |
| M6 matched experiment | Harness and CSVs `590d8e13238bde59e4850d54813ce6c2fac2643d`, report `a11c24b5ba413ee101c9807c465df746394838c9` | Offline checker reconciles 21 lifecycles, 45 orders and 150 receipt rows counting setup. [Report and replay](M6-COMPARISON.md#replay-and-verification) |
| Two clean-checkout author rounds | Exercised `eb4922d6a344987f6b041933bb0ce34ac9c6902d`, recorded at `e3570ee4f7f3a66ff721b9881c1d908593924610` | Six funded identities, 52 action receipts including four expected reverts, 16 statement downloads. Host already had the native tools and Python environment. [Author record](A6-AUTHOR-REHEARSAL.md) |
| Historical patched presentation runtime and former review target | **`a3c5173d9546d017ba322b66ea8096eabdd8ba55`** | Patched lockfile, Vite 6.4.6 and viem’s ws paths at 8.21.0. Production preview, three paths and seven statement downloads rechecked. [Runtime revalidation](VIEWER-DEPENDENCIES.md#revalidation) |
| Dependency assessment, viewer runbook and updated reviewer instructions | `4ff639055507a8f5d2613a557048f3521c3a5dd9` | Records the historical patched run and remaining tooling exposure. [Assessment](VIEWER-DEPENDENCIES.md) · [Reviewer target](A6-REVIEWER.md) |
| Pre-refactor technical recheck | `5b821b93c8cc5480e74a38e4afba66683fd0fca2` | Former independent reviewer target, including the portable mutation runners. [Historical technical recheck](TECHNICAL-RECHECK.md) |

## Before handing in the entry

- [x] **Repository access.** The judge-facing development URL returned HTTP 200 without credentials. Anonymous Git ref discovery returned the development branch and default bootstrap main. That access check preceded the authorized regular merge into main. That merge included development through `5c057fb`. Recheck access to the submitted development revision and video at handoff.
- [x] **Author reproduction evidence.** The recorded tests, exact toolchain, fresh-directory checkout, vendor and compiler pins, frontend lock, local start/reset/stop steps and known download fallbacks are public. The demo uses local accounts, six-decimal mock assets and accelerated Anvil time. [Setup](../README.md#setup) · [Fallbacks](A6-AUTHOR-REHEARSAL.md#setup-and-deviations)
- [x] **Reuse and licenses.** Credit the Unison M1 experiment and its Essentials checkout as the source of unmodified dependencies. Preserve the original Solidity headers and pinned upstream notices for v4-core (file-specific BUSL-1.1 and MIT) and Solmate Owned (AGPL-3.0-only). The viewer’s direct and transitive dependencies retain their own licenses. [Provenance](../experiments/m1/README.md#attribution-and-license-scope) · [Viewer credits](../README.md#reuse-and-licenses)
- [ ] **Independent reproduction.** A second developer uses the implementation pin above from a fresh checkout, records setup deviations, completes two rounds of the three distinct funded runs, and compares Q, receipts, transfers and stale-run checks. Capture their dated result and objections before claiming A6. [Reviewer record](A6-REVIEWER.md#reviewer-record)
- [ ] **Customer decision and economics.** Obtain dated decisions from both roles on the same agreement and evidence of their current reconciliation workload, cost and payer tolerances. Compare against passive, retainer and credible observer settlement. Keep private responses outside Git. [Open gates](../PLAN.md)
- [ ] **Timing and narration.** Rehearse aloud with a stopwatch including clicks, mined receipts, pauses and tab switches. Target 4:30. Check the actual finished file runs under the supplied five-minute limit. Narrate in a human voice, label local mocks and accelerated chain time, and show run IDs at every switch. Show both failed receipts, distinguish vault removal from wallet receipt, pause at the 20 B reserve after refund, and state the matched retainer result and measured cost boundary. [Script and fallback](M8-DEMO.md)
- [ ] **Video and final access.** After recording, inspect legibility and audio, verify duration, upload when authorized and replace the pending field with the actual URL. Open that link and the development README, script, receipt tables and checklist in a signed-out browser. Confirm the intended revision is visible and the video plays without access requests. Local loopback is for reproduction on the judge’s own machine.
- [ ] **Human submission.** Confirm the project ID, branch-specific repository URL, final video link and required fields. An authorized submitter must send the entry and keep the actual confirmation before reporting submission complete.

**Integration completed, 25 November 2026.** The user authorized a regular merge of development into main. Merge `c78173c28105ed768f885a9563f6f9a15aae24b5` preserves the 44 development commits beyond the bootstrap, with development tip `5c057fb0c4bec7b1a8bbdbb365dbbd344d2de97a` as its second parent. Ancestry and identical merged source were checked locally. Main is no longer the bootstrap-only branch. Before any future merge, remind the user to preserve the individual development commits by choosing **Create a merge commit**, record the development tip and obtain explicit merge authorization. After an authorized regular merge, check that the recorded tip is an ancestor of main. No merge, squash or rebase-and-merge is authorized now.


## Prepared final entry — not submitted

**Project ID:** HK-UHI11-1275. **Name:** Unison.

**Short description:** A treasury hires one manager for a single Uniswap v4 liquidity position. A hook measures qualifying position time, a vault limits management authority, and a separate escrow settles pay. In the local demonstration, 180 qualifying seconds earned 60 of a 100 mock-token budget. A blocked manager payment did not prevent treasury principal recovery; 20 earned tokens remained reserved and 40 unearned tokens were refundable.

**Evidence and limitations.** The author’s root run passed 116 tests. All four compiled mutants triggered their expected assertions. Eight browser statements reconciled. The matched retainer delivered equal liquidity, fills and fees. The buyer still needs to justify the extra cost of service-based settlement. Local simulation and pinned forks supply the technical evidence. Independent A6 and security assurance remain open. [Execution evidence](DEVELOPMENT-EVIDENCE.md)

**Fields still requiring actual evidence:** independent reviewer identity/date/results; both customer decisions and supporting costs; final video URL and measured duration; submission confirmation. The user confirmed on 25 November 2026 that none of these records is available yet. Prepared text does not satisfy those fields. Do not substitute the local preview URL for a public video link or claim a submission from the presence of this draft.
