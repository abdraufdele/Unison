# Unison implementation plan

## Scope and current state

One treasury, one manager, one token pair, one fixed-fee Uniswap v4 pool, one active position, one fixed period and a separate compensation budget. Treasury owns principal, idle assets and LP fees. Compensation purchases agreed service, not profit or manager effort.

M1 passed the isolated compatibility/accounting experiment. M2 covers bounded management and independent principal recovery on a local chain with mock assets. M3 service-time accounting passed the local C1 engineering criteria. M4 earned compensation, reserves and terminal refunds passed the local C1 engineering criteria. M5 closeout passed the local C1 engineering review. M6's local matched measurement is complete. Its buyer-specific economic exit remains open. M7 has a verified local agreement page with fixed demo actors. The author replayed payment failure and independent principal exit, swap interruption and recovery, and a separate permitted manager rerange. A block-pinned statement and JSON export reconcile service intervals and transfers. Two author rounds from a clean checkout reproduced the financial outcomes. The M8 judge documents are packaged. Independent A6 rehearsal, a human-timed video and submission remain open. M0 candidate C1 is specified. Customer acceptance and preliminary economic justification remain pending. The user authorizes a narrow experimental hackathon MVP on a local chain with mock assets while A1 and preliminary A2/A3 continue in parallel. Technical completion establishes neither customer acceptance, product-market fit nor economic advantage. Real-fund use and public deployment are outside this decision. Project ID supplied by the user: HK-UHI11-1275.

Read only the next milestone, its applicable gates and relevant source/evidence. Older recurring-epoch proposals are superseded by this single-period plan. Missing feedback stays pending; a deadline or commit target cannot pass a gate.

## Six acceptance requirements and build gates

### A1. Customer and service fit — M0

Obtain dated feedback from at least one prospective treasury operator and one manager on the SAME exact candidate agreement: purchased service, passive delivery, market/inventory risk, payment, early termination and costs. Record role, objections, terms revision and permission for attribution. Interviews/form responses expressing interest alone are not acceptance or product-market fit.

**Pass:** both roles understand and accept the narrow agreement for a stated use case. If they need profit or continuously market-relative depth, revise the service before dependent full-product work. Public case studies establish a problem category, not acceptance of this metric.

**Status:** pending. A research form exists; no accepted customer terms or responses have been verified here.

### A2. Credible simpler comparison — M0 preliminary, M6 final

Compare passive liquidity/owner exit; bounded management with time-prorated retainer/simple escrow; and identical management with Unison service pay. Include an observer plus programmable settlement where it is a credible alternative. Match inventory, funded compensation, duration, fee settings and incoming order intentions. Allow fills/prices to differ when liquidity differs.

**Pass:** reproducible results show a useful service/reconciliation/closeout advantage for the stated buyer, including negative cases. Lower manager pay alone creates no new joint economic value. Record preliminary comparison feasibility and a defensible reason to test while the local experiment proceeds. Final comparison uses the complete lifecycle.

**Status:** buyer-specific gate pending. The [M6 executed comparison](docs/M6-COMPARISON.md) found identical service and execution under the two matched managers. Both recovered a fill passive missed. Unison automated different settlement in interrupted cases. The observer remains modeled and the buyer's need for direct settlement is unverified.

### A3. Justified total cost — M0/M1 preliminary, M6 final

Measure comparable no-hook/hooked active, repeated and ended swap paths; deployment, management, claim, refund and exit. Include operator effort, monitoring, security review, tied-up capital, failed transactions and who bears each cost, including traders. Declare workload, gas-price assumptions, instrumentation and exclusions.

**Pass:** the buyer-specific benefit justifies total added cost. No universal gas threshold; an inconclusive or unfavorable benchmark is not a pass. Recheck provisional economics against final workflow measurements.

**Status:** buyer-specific gate pending. M6 measured full local receipts. The original interrupted one-period premium over the retainer was 9,405,354 gas. The [fresh development comparison](docs/DEVELOPMENT-EVIDENCE.md#fresh-comparison) measured 9,405,402 gas, including 144,106 borne by traders. Review, monitoring, capital pricing and avoided buyer work remain unmeasured. [M6 payer costs and sensitivity](docs/M6-COMPARISON.md)

Historical controlled M1 swap increments: 97,462 outward, 57,636 return and 26,904 after termination. These are diagnostic samples, not a typical average or full transaction-cost estimate. The pool cannot detach its hook after termination.

### A4. Complete closeout and asset rights — M2/M4/M5

Acceptance and full funding precede activation. Cover draft cancellation, expiry and early termination. Freeze entitlement, revoke management, reserve earned-minus-claimed, refund only final unearned compensation, and support independent in-kind principal receipt.

**Pass:** manager compensation transfer fails but treasury termination and principal receipt succeed; restoring transfer capability permits the unchanged earned claim. Repeated actions cannot overpay. Example: funded 100, earned 60, claimed 40 leaves manager reserve 20 and treasury refund 40.

Use recipient-specific compensation failure or an independently failing compensation token. Globally pausing a token also used as principal does not isolate payment failure. State functioning-contract/core/chain and transferable-principal assumptions.

**Status:** passed for the local C1 engineering experiment. Cancellation, termination, effective expiry, delayed close, independent principal receipt and exact earned/refund rights reconciled across the [M5 closeout matrix](docs/CLOSEOUT.md). Recipient-specific failures preserved the independently payable rights. Functioning contracts, transferable principal tokens and chain inclusion remain assumptions. The separate M1 experiment still lacks a supported refund for its residual 100 tokens.

### A5. Challenge invariants — M3–M6

Correct implementation must pass first. In isolated copies deliberately permit earned-reserve theft by refunds, bypass revocation and make exit depend on compensation payment. Each mutant must compile, reach the intended assertion and fail for that defect. Retain M1's omitted-checkpoint mutation regression.

**Pass:** independent balance/time reconciliation, boundary tests and stateful action sequences hold; selected mutants fail as intended. Compilation errors do not count as detection. Preserve unchanged source and failures. Tests are not an audit.

**Status:** the specified local challenges passed. M1/M3 detect omitted pre-change accounting, M4 detects loss of earned reserves, and M5 detects actual post-expiry removal and a payment-dependent failure of principal receipt. The generated closeout corpus reconciles time, token balances, position changes, fees and retries. Coverage is bounded to C1 and the tested action families.

### A6. Reproducible demonstration — M7/M8

Show one actual local journey: acceptance/funding, permitted action, specific forbidden-action rejection, third-party swap interruption/recovery, earned payment, compensation failure, termination, principal receipt and subsequent claim/refund rights.

**Pass:** another developer reproduces pinned setup; two fresh reset runs match state and balances. Label mock tokens, accelerated time, estimates and known limits. Use actual transactions, not chart changes.

**Status:** Two author-run rounds from the published revision matched on service, settlement and principal across six fresh deployments. A second developer still needs to complete the [independent checklist](docs/A6-REVIEWER.md) and supply dated evidence.

## Eight mitigations in priority order

- **R1 / M0,M6 — buy the right service:** validate exact terms and compare credible alternatives; stop expansion if demand or value is unsupported.
- **R2 / M1 — real v4 compatibility:** pin core/toolchain; authenticate PoolManager and active context; verify deployed hook bits, actual callbacks and settled deltas. Bind pool ID + owner + ticks + salt. Keep vault separate from hook; core skips hook-self-initiated callbacks.
- **R3 / M2,M5 — narrow authority:** bound pool, position, tick/width, amounts, execution price/deadline and frequency. Fixed recipients; no arbitrary calls, delegatecall, approval/route selection, inventory swaps, donations, upgrades or ownership escape. Retire old position identity atomically.
- **R4 / M3,M4 — exact accounting:** accrue stored OLD qualification before installing NEW state; initialize from actual state; clip to activation/end/termination. Full-precision cumulative integer arithmetic; no checkpoint-dependent rounding, backdating or denominator reset.
- **R5 / M0,M2,M4,M5 — custody/payment isolation:** separate principal and compensation even for the same token; refunds cannot consume earned reserves; no principal subsidy. Separate termination, claims, refunds and asset withdrawal; test compensation failure without blocking exit.
- **R6 / M0,M3,M6 — metric limits:** validate opening value, age, decimals, token order and tick rounding; calibrate L/width to trade examples. Test drift, manipulation, wide ranges and threshold cliffs. Raw L is not dollars; same-time liquidity earns no elapsed service but may capture native fees. No MEV or continuous-fair-value guarantee.
- **R7 / M2,M3,M5 — liveness/inventory:** qualifying unattended liquidity keeps earning; nonqualifying time does not. Enforce bounds onchain, reject post-termination operations, and revert inventory-infeasible reranges atomically. Pending transactions may execute before termination; chain outages/order remain outside the guarantee.
- **R8 / M4–M8 — trustworthy evidence/UI:** generated ABIs/current addresses, chain time, contract balances and decoded errors; distinguish estimates/pending/confirmed state. Invalidate reset caches. Local reset/time/signing controls bind endpoint + chain + deployment/run, not chain ID alone; no browser secrets.

Record evidence and residual risks at each milestone. This checklist does not establish implemented protections.

## Priority 0 / M0: decide exactly what job is purchased

**Status: candidate specified, gate pending.** [Service specification C1](docs/SERVICE-SPEC.md) covers the proposed agreement. The M0 review covers these requirements.

- Accepted identities, fixed recipients, token/pool terms, duration, funding, activation deadline and budget.
- Exact band/reference derivation, min L, width/tick/amount/deadline/frequency limits and token decimals.
- Terms revision and acceptance binding; draft edits invalidate acceptance; activation checks current acceptance and funding.
- Draft/accepted/funded prerequisites, one activation, cancellation, expiry/termination, reserved earnings, refunds and in-kind exit. No renewal or automatic replacement.
- Exact formula, boundary cases, errors, interfaces and worked examples; label candidate values versus customer-approved ones.
- A1 feedback plus preliminary A2/A3 decision. Prepare outreach materials; send messages only when explicitly instructed.

**Exit:** exact rights and service are unambiguous, A1 and preliminary A2/A3 pass. If not, continue bounded validation; do not disguise a technical prototype as a validated product.

## Priority 1 / M1: prove the plumbing with real v4 contracts

**Status: bounded PASS on Windows, 19 November 2026, reproduced on native WSL, 23 November 2026.** See [M1 status and evidence requirements](docs/M1-STATUS.md). Reuse that evidence and source; do not restart M1 because older docs describe it as unstarted.

Direct PoolManager vault ownership; explicit vault checkpoint before liquidity changes and refresh after; afterSwap observes third-party swaps. The narrow experiment uses beforeAddLiquidity admission control. No remove/donation/return-delta/dynamic-fee callbacks, canonical PositionManager NFT or Permit2 requirement.

**Regression:** real add/swap/remove, full identity/context authentication, settled deltas, correct address flags and callback trace; omitted pre-change checkpoint must fail the intended duration assertion. This depends on correct vault checkpoints, not independent hook enforcement. Pin actual versions; changes to ownership/periphery paths require a new compatibility check.

## Priority 2 / M2: enforce the treasury's control and exit

**Experimental local dependency:** candidate C1 and replay of the bounded M1 foundation on the target toolchain. A1 and preliminary A2/A3 stay open in parallel. The [C1 specification](docs/SERVICE-SPEC.md) records the acceptance boundary and local build decision. Implement AgreementVault acceptance/funding coordination and one immutable active agreement. Manager may only add/remove/rerange within agreed bounds using available inventory. Collected fees stay treasury-owned.

**Complete for the local C1 engineering experiment.** The funded vault activates against a fresh preflight and owns the seed in the pinned core. Real-core tests cover authorized add, remove, reopen and atomic rerange, every M2 rejection path, rollback of a one-unit inventory shortfall, immediate revocation and independent treasury receipt. Pre-activation cancellation and its separate refund remain available. See the [manager-operation evidence](docs/MANAGER-OPERATIONS.md) and [activation and recovery evidence](docs/ACTIVATION-RECOVERY.md). The [M5 closeout review](docs/CLOSEOUT.md) covers the complete local asset-rights gate.

**Exit:** permitted adjustment succeeds; unauthorized caller/recipient/pool/range/amount/deadline paths fail. Rerange failure preserves old state atomically. Revocation blocks subsequent manager operations; treasury removes and receives assets without manager cooperation. No generic executor.

## Priority 3 / M3: add an attributable service clock

**Complete for the local C1 engineering experiment.** The real-core swap, position, independent interval and mutation results are in the [service-clock evidence](docs/SERVICE-CLOCK.md).

**Depends:** M2. ServiceHook tracks exact active position: sufficient L, full agreed-band coverage, in-range tick, permitted fees and active period. A fresh valid opening reference fixes the sole band; later oracle failure cannot gate settlement/exit.

Checkpoint old state before changes; install actual new state. Retired/unrelated positions earn nothing. A qualifying passive position earns without activity. No token transfers, oracle reads or unbounded loops on the swap path.

**Exit:** known real-swap intervals reconcile, lower-inclusive/upper-exclusive semantics hold, same-time transitions add zero seconds, delayed checkpoints clip correctly and no pre-activation/post-end earnings occur. Define interfaces/events now; a simple wireframe is enough.

## Priority 4 / M4: fund and calculate manager compensation

**Complete for the local C1 engineering experiment.** The [settlement evidence](docs/COMPENSATION.md) records the cumulative rounding, fixed recipients, exact transfer and failure regressions, and compiled reserve mutation.

**Depends:** M3. CompensationEscrow receives/reserves one budget before activation. Supported token transfers must match actual received amounts.

earned = floor(budget × cumulative qualifying seconds / original duration)
claimable = earned − claimed

Use base units/full precision. Claims pay only fixed manager recipient; repeated claims cannot double-pay. Refund only final unearned funds after cancellation/closeout, never currently unearned active-period funds. Exclude or explicitly reconcile unsolicited donations.

**Exit:** 100 six-decimal mock B × 180/300 = 60,000,000 units; one second = 333,333 units. Claims/refunds/earned reserves conserve funds. Expose terms, qualification reasons, seconds, earned/claimed/reserved/refundable amounts and reconstructible transition events.

**Frontend:** begin thin real read-only UI when these interfaces stabilize. No per-second transactions or mandatory indexer/database.

## Priority 5 / M5: prove complete closeout under failure

**Complete for the local C1 engineering experiment.** The [closeout review and evidence](docs/CLOSEOUT.md) maps all product writes, terminal rights, failure assumptions and targeted mutations.

**Depends:** M4. Termination checkpoints, freezes entitlement and revokes authority without transferring compensation. Keep pull-claim, unearned refund, liquidity removal and principal receipt separately callable. Natural expiry disables management even without a transaction at the exact deadline.

**Exit:** A4 passes for early termination, expiry, cancellation, repeated calls, delayed transactions and residual assets. Prove a manager-specific payment failure, independent principal receipt, then restored manager claim. Exit returns current assets, not guaranteed original quantities/value.

## Priority 6 / M6: prove what Unison improves

**Measurement complete; economic exit pending.** The [M6 report](docs/M6-COMPARISON.md) reconciles seven scenarios across three executed arms and assesses the observer alternative.

**Depends:** M5 for final evidence. Recheck A2/A3 using full lifecycle. Include passive flat case, feasible recovery, unavailable inventory, delayed execution and external-price drift. Record native LP fees, service, compensation, inventory, marked value, slippage, capital/opportunity costs and gas separately.

**Exit:** A5 detects selected defects; final buyer-specific economic comparison supports the claim. Keep unfavorable/inconclusive outcomes; revise if the simpler alternative wins.

## Priority 7 / M7: finish one usable judge page

The [local agreement viewer](docs/LOCAL-VIEWER.md) reads a verified deployment at a single mined block. Browser checks cover funded, qualifying, interrupted and terminal states. Its fixed local actions also have mined receipt and balance evidence for interrupted service and payment-failure closeout. The downloadable event-based statement passed author browser checks for funding, active service, interrupted service, permitted manager rerange, termination and unfinalized expiry. Independent M7/A6 rehearsal remains open.
- One agreement page: accepted terms, owner/manager roles, separate balances, qualification/reasons, earned/paid/unpaid/refundable, supported actions and closeout statement.
- Reconstruct payment from events/initial state; contract entitlement remains authoritative. Export a readable statement and JSON with terms, interval/block coverage, balances, obligations and transaction references. Report incomplete data.
- Distinguish claimable/refundable from actually transferred funds. Explain nonqualification without assigning manager blame.
- Generate ABIs/addresses; handle account/network mismatch, pending/revert/read failure and stale reset state.
- Local scenario controls execute real swaps/time advances under R8. Supported plain mock ERC20s only initially.
- Safe ownership is optional after core correctness; suitable opening-reference adapter is conditional. Simulation and professional manager adapters are deferrable.
- The [Safe and wallet lifecycle checklist](docs/DEVELOPMENT-EVIDENCE.md#safe-and-wallet-lifecycle-checklist) records the verified C1 baseline, evidence identities, seven requirements and their delivery order.

**Exit:** a user completes the actual flow without terminal work, can inspect why pay changed and can exit despite manager compensation failure. No simulated success screen substitutes for enforcement.

## Priority 8 / M8: package, rehearse and submit

**Packaging published. M8 and A6 remain open.** Use the [judge README](README.md), [pitch, timed script and inspection route](docs/M8-DEMO.md), [criteria and hard questions](docs/M8-JUDGE.md) and [submission checklist](docs/M8-SUBMISSION.md). The checklist names the exact runtime and evidence revisions for HK-UHI11-1275.

**Depends:** M5–M7 and A1–A6 evidence. README leads with implemented promise, status, exact pinned setup/test/reset commands, architecture, evidence and limits. Preserve third-party licenses and accurately distinguish reused/new work, including Essentials reuse. Claim integrations only with code/action evidence.

Verify another developer's fresh setup and two reset replays. Record a human-narrated video under the supplied five-minute limit. Confirm public repo/branch and submission access. No invented audit, novelty, customer, profit or prize claims.

### Before integrating the submission branch

Remind the user to choose **Create a merge commit** when merging development into main. Preserve original individual commits and IDs; no squash, rebase-and-merge, backdating or force-push. Obtain explicit merge authorization. Record the development tip before merging and verify it is an ancestor of the resulting main; inspect the commit list and default branch before submission. No merge is authorized by recording this reminder.

## Schedule and scope cuts

Use dependencies, not stale target dates, to choose work. Supplied organiser deadlines (Africa/Lagos): progress updates 24 November and 1 December 2026 at 08:59; final submission 4 December 2026 at 08:59; Demo Day 11 December. These dates are user-supplied, not a freshly verified extension.

Cut Safe, professional adapters, public testnet, extra charts and polish before weakening service gates, accounting, exit or evidence. Replan against actual progress.

## Commit workflow

Aim for 12 meaningful commits per working day over the user's seven-day build period; 84–90 is a target, not proof of quality or permission to bypass gates. No empty commits, padding, backdating or artificial rewrites. Keep coherent implementation and its necessary tests together.

Inspect status/diff, check the change, stage explicit files, commit and push only to the agreed GitHub destination/branch after first-push scope is established. Verify pushes. No reset/clean, force-push, merge or rewriting pushed history without authorization. A successful local commit is not a successful push.

## Progress record

- M0/A1 and preliminary A2/A3 remain pending. M1 through M5 passed their local engineering criteria. A4 and the specified A5 challenges passed for local C1. A6 remains open.
- Latest documentation review: 25 November 2026. Historical evidence dates are preserved. Research form prepared/published; no customer acceptance inferred.
- Next evaluate dated evidence from a treasury operator and manager on C1, their existing reconciliation costs and their tolerance for the measured payer burdens. The M7 interactive page has an author-verified payment-failure journey. The agreement statement now reconciles events with the contract snapshot. Both fresh author rounds covered the permitted manager action, interruption/recovery and failed payment. The independent checklist is ready for a second developer.
- Parallel validation task is to evaluate user-supplied private evidence from one treasury operator and one manager for the same C1 use case. Obtain their separate dated decisions, one reconciliation example with units and payer, and acceptable evidence and cost limits. If evidence is unavailable, keep the worksheet unsent pending explicit outreach instructions. Recalculate the comparison against the simplest arrangement that meets the stated job.
- Open decisions include buyer-approved depth, budget, duration, operational bounds and a suitable opening source. C1 proposes the conversion, contract interfaces and failure behavior. Full-product evidence is pending.
- Record each substantive work session: terms/source revision, actual commands/results, commit/push status, evidence location, residual defects and next dependency-ready action.

- Repository setup, 23 November 2026: public abdraufdele/Unison created; bootstrap commit e87b16b published on main. Development branch development tracks origin/development. Repository-local author: abdraufdele <apexnaijatv124@gmail.com>. WSL Git uses the existing authenticated GitHub CLI credential helper. No credentials are stored in tracked files. This records Git setup, not a product acceptance pass.

- M0 specification session, 23 November 2026. Published [C1](docs/SERVICE-SPEC.md) in commit `bc3d08f` on `origin/development` and verified the live branch with `git ls-remote`. The agreement uses mock terms for review. Reviewed actor permissions, fixed recipients, state reachability from Draft through each terminal reason, and separate exit/claim/refund rights. Local Python checks reconciled the five settlement examples, zero/funded cancellation, cumulative rounding, prior claims and refund order. Decimal calculations checked the aligned opening band, seed inventory and illustrative trade. Relative links resolved and the staged spec passed `git diff --cached --check`.
- A1 still needs dated feedback from both roles accepting the same revision for a stated use case. Preliminary A2 needs a credible service or reconciliation advantage over passive LP, a retainer and observer-based settlement. Preliminary A3 needs buyer-specific benefit against estimated total costs, including trader and operator costs. No role feedback or comparison results were obtained in this session. M0 remains open and the bounded M1 result stands.

- M0 validation preparation for C1 (`bc3d08f`). Prepared a private, unsent two-role review worksheet in the ignored local validation directory. The [public comparison and cost worksheet](docs/C1-COMPARISON.md) matches four arrangements across flat, interrupted and infeasible-recovery cases. It separates payer workloads, diagnostic M1 measurements, synthetic assumptions and missing inputs. The illustrative three-swap trader increment at 10 gwei/gas is 0.00182002 ETH. Other lifecycle costs and buyer benefit remain unknown.
- Preparation checks covered scenario payouts and reserves, inventory bounds, cost units and sensitivities, local links and Git exclusion of the private directory. No customer responses, outreach or new M1 measurements. A1 and preliminary A2/A3 remain pending. The preparation and its checks are recorded together in the development commit titled “Prepare the C1 comparison and validation worksheets”.

- Experimental-build decision and M1 reuse preparation. The [import record](experiments/m1/README.md) identifies five byte-preserved files, the two archive manifests, Windows evidence, reference Git objects, dependency licenses and material M1/C1 differences. Verified source and dependency pins, compiler hashes, local Forge version, import hashes and public-file scope. Published the isolated import in commit `b9629d9` on `origin/development`. Local links, Bash syntax and Forge config/remapping checks passed. WSL setup and replay are pending. No dependency installation, compilation, test execution or deployment took place in this session. The complete A4 closeout, A5 regression challenges, final A2/A3 measurement and A6 demonstration remain engineering/evidence gates.

- Native WSL replay, 23 November 2026. Published the [replay report](experiments/m1/WSL-RESULT.md) at `f0a4893` on `origin/development`. Verified both dependency revisions, clean checkouts, compiler hash and effective Forge settings. The original and corrected assessment suites passed 19 and six tests with exit 0. The single omitted-checkpoint mutant compiled and exited 1 at the intended accounting assertion. At expiry, the trace reconciled 200 qualifying seconds, 200 paid and 100 left in escrow. All five imported hashes passed before and after. Private commands, raw outputs and exit codes remain in the ignored evidence directory. A1 and preliminary A2/A3 are pending. C1 acceptance, funding and complete closeout still require their own implementation and tests.

- First local M2 slice. Published the [acceptance implementation](src/AgreementVault.sol), [tests](test/unit/AgreementVaultAcceptance.t.sol) and canonical C1 field list together at `9aaa170` on `origin/development`. The vault commits to the exact candidate numerical schedule, roles and fixed recipients, full pool/custody identities and opening rules. Revisions clear both approvals even when restoring previous bindings. A live observation, derived ticks and start time belong to future activation.
- Executed the root Foundry suite offline with Forge 1.8.7 and native solc 0.8.26+8a97fa7a. Compilation succeeded, 12 tests passed, zero failed or skipped, exit 0. The wrong-hash case ran 256 fuzz inputs. Checks included a separately encoded commitment vector, single-field revisions on the same vault at the same revision, invalid-input rollback, both cutoff boundaries, event idempotence and the two-method write surface. Formatting and all five M1 import hashes passed. Local test calls establish the consent behavior only. A1 and preliminary A2/A3 remain pending, along with complete M2 control/exit and later accrual, compensation, refunds and payment-failure closeout.

### C1 funding and pre-activation recovery, 24 November 2026

Published the contracts and their tests together at `eb13a58` on `origin/development`. Verified the full implementation commit with `git ls-remote --exit-code origin refs/heads/development`. The [root setup](README.md#setup) records the exact commands, native pins and constructor/revision wiring. No external Solidity dependencies were added.

| Evidence | Local result |
| --- | --- |
| Complete root suite | Native Forge 1.8.7, pinned Linux solc 0.8.26. Compiled successfully. 12 acceptance, 15 funding and 9 cancellation/recovery tests passed (36 total, 0 failed, 0 skipped, exit 0). Wrong-hash fuzz test ran 256 inputs. |
| Atomic custody | Treasury debits were 2,000,000,000 A and 2,100,000,000 B units. Vault credits were 2,000,000,000 of each, escrow credit was 100,000,000 B. A failure on each leg, including the final budget leg, restored balances, allowances, credits and Accepted state. Prior gifts, wrong decimals or wiring, short receipts, unexpected debits and malformed transfer results were tested. |
| Cancelled custody | Cancellation made no transfer. A blocked escrow-to-treasury B route left 100,000,000 B due while the treasury withdrew both principal amounts. Enabling that route paid the original refund once. Failure on the second principal transfer rolled back the first. Escrow gifts remained outside refund rights. |
| Integrity | Root Solidity formatting and staged whitespace checks passed. All five M1 SHA-256 checks passed before and after (exit 0). The acceptance suite and M1 import were preserved. |

No unresolved root test failures. A1 and preliminary A2/A3 remain pending. M2 still needs activation and bounded management. Accrual, earned reserves, manager payment failure with a live position, and complete closeout remain open. Next implement the M2 activation prerequisites described above.

### C1 opening-reference prerequisite, 24 November 2026

Published implementation, independent arithmetic oracle and tests together at `f25c557` on `origin/development`. Verified the pushed implementation ref with `git ls-remote --exit-code origin refs/heads/development`. The [opening-reference note](docs/OPENING-REFERENCE.md) records the accepted mock interface, exact comparison, overflow bounds, expressible feed boundaries and future activation call. The canonical terms commitment vector still passes.

| Check | Result |
| --- | --- |
| `python3 scripts/check_opening_grid.py` | Exit 0. Independent integer recurrence certified all 29,575 grid floors and emitted digests and selected feed vectors. All three Solidity digest comparisons matched. Parity produced [−120, 120). |
| Complete root suite using the [pinned native command](README.md#setup) | Exit 0. 51 passed, 0 failed, 0 skipped across five suites. These include 8 band, 7 adapter/vault, 12 acceptance, 15 funding and 9 cancellation tests. Coverage/minimality and wrong-hash fuzz tests ran 256 inputs each. |
| Integrity | `forge fmt --check src test`, staged whitespace checks and all five M1 SHA-256 checks passed (exit 0). The existing clean core checkout supplied the MIT math imports through a root-relative remapping. |

No unresolved suite failures. The adapter asserts the reported price and completion. Live-source selection and independent truth verification remain open. Next validate the actual pool and seed feasibility. Activation, bounded management, service accrual, settlement of earned rights and live-position exit still require implementation. A1 and preliminary A2/A3 remain pending.

### C1 read-only activation preflight, 24 November 2026

Published implementation and real-core tests together at `f5fea1e` on `origin/development`. Verified the implementation tip with `git ls-remote --exit-code origin refs/heads/development`. The [preflight report](docs/ACTIVATION-PREFLIGHT.md) gives the exact commands, custody and pool checks, four observed quotes versus signed principal deltas, local fixture assumptions and upstream license scope.

- Complete pinned root suite passed 66 tests across six suites, 0 failed, 0 skipped, exit 0. All 51 previous tests passed. All 15 preflight tests passed. Both existing fuzz tests ran 256 inputs. An initial targeted run exited 1 when a test chain-ID change carried into a cutoff assertion. Isolating the chain fixture preserved both checks. No unresolved suite failures.
- Four traced tests passed, exit 0. At parity the seed required exactly 598,173,777 units of each token. Interior and one-sided edge quotes also equaled actual core principal debits. All six one-unit-short trials failed settlement and rolled back. A downward swap to parity left stored tick −1 and selected the correct side of tick zero.
- Native formatting, independent grid check, staged whitespace and all five M1 import hashes passed. The existing core checkout and its pinned Solmate submodule supplied the dependencies. All writes to pools and positions were confined to the local test fixtures.
- M2 remains partial. Design terminal recovery before accepting vault-owned liquidity. Then implement atomic activation and seed ownership with a fresh in-transaction preflight. Product hook wiring, context authorization, bounded management, accrual and complete live-position exit remain open. A1 and preliminary A2/A3 remain pending.

### Atomic treasury activation and terminal principal recovery, 24 November 2026

Published the vault, product hook and real-core integration tests together at `50b2e93` on `origin/development`. Verified the implementation tip with `git ls-remote --exit-code origin refs/heads/development`. The [recovery design and executed evidence](docs/ACTIVATION-RECOVERY.md) records the state transitions, constructor deployment, callback boundaries, base-unit reconciliation, commands and retained limitations.

- A CREATE2-deployed product hook admitted the vault's single seed under salt 1. Core confirmed 100,000,000,000 L, with 598,173,777 A and B base units each spent at parity. Independent additions failed and an external trader's swap succeeded.
- After the swap, removal returned principal of 698,218,788 A and 498,228,754 B units, plus 301,038 A units in fees. Idle and subsequent withdrawals delivered 2,100,346,049 A and 1,900,054,977 B units in total. Principal recovery succeeded while adapter and escrow calls failed. Exact expiry enabled exit before finalization and a later finalizer recorded the original end. The full 100 B budget remains locked after activation pending earned-right settlement.
- Complete pinned root suite passed 77 tests in seven suites (66 previous, 11 new), 0 failed, 0 skipped, exit 0. Both previous fuzz tests ran 256 inputs. An initial targeted invocation stopped at discovery (exit 1) because Forge reserves the `testFail` prefix. Renaming that test preserved its assertions. No unresolved suite failures. Trace replay, runtime size, formatting and all five imported hashes passed (exit 0).
- Runtime bytes were 21,743 for AgreementVault, 1,158 for ServiceHook and 1,887 for CompensationEscrow with the normal EVM limit. The M1 tree and root configuration were preserved. M2 remains partial. Next implement and challenge bounded manager adjustments and revocation. Service-time accounting, earned reserves, full compensation-failure closeout and customer/economic gates remain open.

### Bounded manager operations and M2 exit, 24 November 2026

Published the vault, hook, fixed opening-quote helper and real-core tests together at `e74dbac` on `origin/development`. The starting checkout was clean at `67d80c6`. The push succeeded and `git ls-remote --exit-code origin refs/heads/development` returned `e74dbacadacba55b2250e584808e922aaf5f8aa8`. The [management report](docs/MANAGER-OPERATIONS.md) records the interface, identity, per-leg authentication, size-driven extraction, independent balance checks and replay commands.

- The final pinned root suite passed 92 tests across eight suites, including all 77 prior tests and 15 manager tests. Zero failed or skipped, exit 0. Both fuzz tests ran 256 inputs. The separate rollback trace, product size build, opening-grid check, Solidity formatting and all five M1 SHA-256 checks passed, each with exit 0.
- Both currencies exercised the hard 2,000,000,000-unit gross input cap despite fee offsets. Removal minimums excluded LP fees. A 1-unit B shortfall on the second rerange leg restored old core liquidity, balances, identity and cooldown. Funding that unit allowed the same request to open 167,676,999,673 L under salt 2 at the same timestamp.
- Same-timestamp chain ordering and exact expiry revoked all manager actions. Terminal exit after a rerange and an external swap reconciled treasury principal and fees outside the manager price envelope with the adapter and escrow unavailable. The activated 100,000,000 B budget stayed in escrow.
- Forge runtime/initcode bytes were 22,947/34,165 for AgreementVault, 1,390/1,807 for ServiceHook, 1,887/2,161 for CompensationEscrow and 4,895/4,921 for OpeningQuote. All fit normal limits including constructor arguments. Dependency pins and file-specific license notices were preserved. The staged implementation excluded local logs, build artifacts and dependencies.

M2's local control and principal-exit criteria passed. There are no unresolved root test failures. Next implement M3 service time at the pre-change and post-change boundaries, including activation, external swaps, termination and expiry. Earned reserves, claims, post-activation refunds and complete payment-failure closeout require M4/M5. A1 and preliminary A2/A3 remain pending.

### C1 cumulative service clock and M3 exit, 24 November 2026

Published implementation, real-core tests and the isolated ordering challenge together in `4fb37a3` on `origin/development`. The starting checkout and live branch were at `c039822`. After push, `git ls-remote --exit-code origin refs/heads/development` returned `4fb37a3625e5bc32c3bf459a02b02427f2c6614a`. The [M3 evidence](docs/SERVICE-CLOCK.md) records the hook interface, custody lock, observation boundaries, retained limitations and replay commands.

- The external trader reached stored tick 120 at elapsed 90 and −1 at 210. The independently summed intervals [0, 90) and [210, 300) gave Q = 180. Passive delivery gave 300 and early termination at 120 gave 120. Below-minimum, empty, unrelated, extended and retired positions, same-time changes, delayed close and partitioned checkpoints reconciled.
- The one-unit rerange shortfall restored persisted Q, timestamp, core position, balances, grants and cooldown. Its successful retry credited the original interval exactly once. Principal and LP fee receipt succeeded with adapter and escrow calls blocked, retaining frozen Q.
- The pinned root suite passed 100 tests in nine suites, zero failed or skipped, exit 0. Three fuzz tests each ran 256 inputs, including 6,144 clock sequence steps. The separate three-test trace passed. The omission mutant compiled successfully and failed the unchanged full-removal assertion with `OldIntervalLost(100, 0)`, exit 1. The compiler-message check was corrected to accept a successful build with warnings. Both copies retained byte-identical tests.
- All four product runtimes and initcodes with arguments fit normal limits. Vault runtime is 23,764 bytes with 812 bytes available. Formatting, size build, grid check and all five original M1 hashes passed. Mutation copies, logs and build artifacts are ignored.

M3's local engineering criteria passed. Next implement M4 cumulative funded compensation with fixed-recipient claims, protection of unpaid earned reserves and terminal unearned refunds. Complete payment-failure settlement remains an M5 dependency. A1 and preliminary A2/A3 are pending.

### C1 earned compensation and M4 exit, 24 November 2026

Published the implementation, tests and mutation replay together in `8a1132c` on `origin/development`, from a clean starting tip of `95fdbf1`. The live ref after push was `8a1132c0475ba6a8d5c09a040a25c8065e0289fb`. The [M4 report](docs/COMPENSATION.md) records the settlement interface, formulas, exact receipts, sizes, commands and scope.

- The exact funded budget of 100,000,000 units and the original 300-second duration produced E = 60,000,000 at Q = 180. A claim at one second paid 333,333 and a second claim at three seconds paid 666,667. Full service, early close, both pull orders and exclusion of gifts reconciled to actual balances.
- At Q = 120 the manager received 40 B. At Q = 180 the manager-specific transfer failed and treasury terminated at the same timestamp. With the adapter also failing, principal exit delivered 2,100,346,049 A and 1,900,054,977 B units including fees and idle assets. The treasury received its separate 40 B refund, escrow retained the 20 B unpaid reserve and the restored manager route paid those 20 B. Final C = 60 B, R = 40 B, accounted escrow = 0. A separate blocked refund left its 60 B recoverable through principal exit and manager payment.
- Full pinned root suite passed 109 tests in ten suites, zero failed or skipped, exit 0. Three fuzz tests each ran 256 inputs. Both traced failure cases passed. The one-expression reserve mutant compiled (exit 0) and the unchanged test failed on the intended raw escrow balance, expected 20,000,000 and actual zero (exit 1). Formatting, grid, product size and all five M1 hashes passed.
- Vault runtime is 23,891 bytes, leaving 685 bytes. All four products fit normal runtime and argument-inclusive initcode limits. The local M4 payment criteria passed. M5 closeout review, broader invariant challenges, final economic measurement, customer validation and the reproducible demonstration remain pending.

### M5 closeout review and targeted invariant challenges, 24 November 2026

The clean starting checkout and live development ref were `b9f011c`. Published the tests and isolated mutation replay in `41bf167` on `origin/development`. A transient DNS failure on the first push cleared on retry. The live development ref then matched `41bf167d6e97664d98e14ece79d04ce47742b79e`. The [closeout matrix](docs/CLOSEOUT.md) records code paths, tests, remaining assumptions, commands and observed failures.

- No product defect was demonstrated under the tested assumptions. The funded rights, callback authorization, frozen entitlement and principal-exit paths required no source or ABI change. The local M5/A4 engineering gate and specified A5 challenges passed.
- 32 seeded lifecycles exercised 768 shuffled active/terminal action slots, 16 early terminations and 16 expiries with delayed finalization. Independent accounting reconciled 110 positive claims, 32 positive refunds, 32 live exits and 52 positive principal withdrawals. Each run exercised manager and refund route failures, a reverted second rerange leg and a successful retry.
- Both mutants compiled, each with exit 0. The expiry mutant performed the forbidden full removal at exact end and the test found actual core L zero instead of 100,000,000,000. The mandatory claim in the exit mutant hit the blocked manager route and treasury was short 498,228,754 B base units. Both native tests exited 1 at their intended balance/position assertions. Prior checkpoint and reserve mutation evidence remains applicable.
- Full pinned suite passed 115 tests in 12 suites, zero failed or skipped, exit 0. The three existing fuzz tests each ran 256 inputs. An initial 32-sequence single test transaction exhausted the normal gas limit. Four eight-seed transactions passed with the same seeds and assertions. Focused traces, product sizes, formatting and all five imported M1 hashes passed. Vault runtime remains 23,891 bytes with 685 bytes available.
- Next undertake M6 matched scenarios and total-cost measurement. The M4 interfaces remain stable for thin reads. Customer acceptance, economic justification and a reproducible full demonstration remain open.

### M6 matched lifecycle and cost measurement, 24 November 2026

The interruption left a successful comparison build and no scenario receipts. Reused the compiled artifacts. The first interrupted Unison/retainer comparison reconciled before the remaining workloads ran on the same disposable local chain. Published the harness, checks and public ledgers in `590d8e1`. Verified the live development tip at `590d8e13238bde59e4850d54813ce6c2fac2643d` after push. The [cost and decision report](docs/M6-COMPARISON.md) records the measured boundaries and replay.

- Reconciled 21 lifecycles, 45 incoming orders and 150 receipt rows counting common and arm setup once. Tracked actual order balances, fee growth, qualifying intervals, LP and idle principal, compensation rights and marked final holdings. Both managed arms had identical Q, liquidity, fills, treasury fees and principal on every path. Their feasible rerange added 180 qualifying seconds over passive and filled a 50 B order. Both infeasible attempts reverted. Both isolated payment failures preserved the same independent exit and 20 B earned reserve.
- The interrupted retainer and Unison paid 100 B and 60 B for the same 180 seconds. The incremental treasury, manager and trader gas was 9,190,339, 70,909 and 144,106 respectively. The joint 10-gwei hurdle was 0.09405354 ETH plus any incremental non-gas costs. Payout redistribution supplies no joint savings. Drift left full fixed-band pay intact despite adverse execution against the external mark.
- Checked all 58 source hashes referenced by the deployed artifact set, compiler settings, dependency pins, Solidity formatting, offline result reconciliation and staged public scope. Product source, shared fixtures, root configuration and the M1 import were unchanged. The prior 115-test product result stands. The observer's certified settlement, disputes, latency and costs remain modeled.
- The local M6 measurements are available. Its buyer-specific exit, A1 and preliminary/final A2/A3 remain pending. Next apply evidenced workload counts, existing dispute/reconciliation costs and payer tolerances to the measured hurdles, and obtain both roles' assessment of the same terms when feedback is available. No outreach, frontend work or deployment beyond the local fixture.

### M7 local read-only viewer, 24 November 2026

From clean, remote-verified `a11c24b`, published the viewer, ABI export, browser checks and disposable setup at `df37120`. After push the live development ref was `df37120da77532be3d2b8c673337aa67cf704723`. The [local runbook](docs/LOCAL-VIEWER.md) records start, stop, identity-bound reset, commands, tool versions and actual state checks.

- The launcher reuses the M6 product deployment and real hook CREATE2 procedure, with an optional stop after funding and random per-run agreement ID. The manifest lives in memory and binds loopback RPC, chain, funded block/hash, addresses, code hashes and the verified artifact build. Browser reads use the compiled read ABIs and one block number, followed by a block-hash recheck.
- TypeScript and the production build passed. A real headless Chromium opened the built page. Independent IPC reads and browser assertions agreed at funded block 22, qualifying block 24, interrupted block 25 and terminal block 26. Each page snapshot pinned 46 contract/code reads to its displayed block. Q progressed from 0 to 1 to 90 seconds. At termination escrow held 100 B, including 30 B reserved and 70 B refundable, with no payment or refund transferred.
- The browser retained clearly stale values across transport and read failures, cleared values on identity errors, and rejected missing code, wrong chain, wrong marker, absent manifest and a saved manifest after an actual reset on chain 31337. The launcher rejected a mismatched reset ID. Normal state pages had no console errors or narrow-screen horizontal overflow. Test services were stopped. Runtime manifests, signer material, dependencies and build output were excluded from the commits.
- The M1 import, product contracts, shared Solidity fixtures, root build configuration and recorded M6 CSVs stayed unchanged. The M6 offline checker verified all 21 ledgers, 45 orders and 150 receipt rows. The retained 115-test product result applies. Next implement and verify a reconstructible event-based statement/export in a separate task. Tested writes, the complete failure/exit journey and independent A6 reproduction remain pending. A1, A2 and A3 still require customer and economic evidence.

### M7 interactive local demo, 25 November 2026

Published the fixed local actor controller, page and browser checks in `e04496f`. The live `origin/development` ref after that push was `e04496f61e4c136bae9a9eabb0c203abd07b207b`. The [runbook](docs/LOCAL-VIEWER.md#run-the-payment-failure-journey) records all 19 local transaction hashes, both run IDs and the bounded replay command.

- Chromium verified the funded-to-settled path at blocks 22–38. At Q=180 the escrow showed 60 B earned, 40 B already paid and 20 B reserved. The blocked 20 B claim reverted with the B token's transfer error. With the route still blocked, treasury terminated, removed all liquidity and received 2,100.346049 A and 1,900.054977 B including idle assets and fees. Treasury then received 40 B from escrow. Restoring the manager route paid the remaining 20 B. Repeated claim and refund transferred zero.
- The identical bounded manager removal simulated successfully at active block 29. Its transaction at block 31 reverted with `InvalidPeriod()`. Both intended failures preserved payout rights and token balances. In the separate swap run the position stopped qualifying at tick 120 and resumed at tick −1. Q remained 90 during the interruption and reached 120 by termination. Independent balance reads agreed with the page.
- Exact Host, Origin, run token, anchor, bindings, stage, actor and parameter checks constrain actions. Concurrent activation produced a single receipt. Page load and refresh produced none. Stale-run, duplicate, control/RPC failure and read-identity checks passed. A failed early reset assertion led to waiting for the replacement onchain ID to appear in the page. The complete corrected browser replay exited 0. TypeScript, the production build, ABI check and formatting passed.
- Product contracts, M1 import, M6 measurements, package lock and dependencies were unchanged. The retained 115-test product result applies. Next reconstruct the statement from events and reconcile its coverage against contract state. A6 needs another developer to reproduce the pinned setup and full fresh-run scenario, including a permitted manager action. Final presentation and A1/A2/A3 customer and economic evidence remain open. M6 measured matching liquidity under the bounded retainer. The 40 B refund reallocates the existing budget.

### M7 reconstructible agreement statement, 25 November 2026

Published the collector, block-pinned statement section, JSON download and replay checks at `477d950`. The live development ref after that push was `477d950993f50dd373d90b909836c1c1ce666c65`. [Runbook, schema and browser evidence](docs/LOCAL-VIEWER.md#agreement-statement-and-json-export)

- Coverage starts at vault deployment block 15. Both party acceptances and the funding transaction at block 22 are included. The collector compares bounded product logs with canonical transaction receipts, sums old qualification across checkpoint intervals, applies the original 300-second denominator, and reconciles rights, liquidity and movements against historical contract and token reads. The page rechecks its displayed block hash before enabling the download.
- Seven Chromium downloads covered funding, active projection, blocked-payment termination, refund, restored final payment, interrupted service and contract-effective expiry without finalization. Closeout reconciled 180 s, 60 B earned, 40 B initially paid and 20 B reserved. The 40 B refund preserved that reserve and restoration paid it. At expiry, stored Q was zero and the end-clipped projection was 300 s. No close event had been emitted. Downloading left each fixture head unchanged.
- A further Chromium download read the retained 12-event interruption history on the previous demo deployment at block 27. It reconstructed 90 s in range, 120 s outside, then 30 s back in range. It used a read-only test listener to access the existing owned IPC chain without replacing its running launcher.
- Missing, duplicate and out-of-order historical logs were rejected. Browser checks rejected stale run identity, unknown schema/build, transport failure and a mismatch with contract earnings. TypeScript, production build, compiled ABI check, formatting and existing read-fault checks passed. Product contracts, M1 imports, M6 evidence and dependency pins were preserved. The retained 115-test product result applies.
- The local node supplies all blockchain evidence. Its consistency checks do not prove provider completeness. The historical hook failure mask and failures outside the demo receipt journal have limited coverage. Next demonstrate a permitted bounded manager action. Independent fresh setup and A6 rehearsal, final presentation and A1/A2/A3 customer and economic validation remain open.

### M7 permitted manager journey, 25 November 2026

Published the fixed manager branch, browser controls and isolated replay at `104ca71`. The live development ref after that push was `104ca711b991925e1e6b5e9463c897060983db72`. The [runbook](docs/LOCAL-VIEWER.md#permitted-manager-rerange-on-a-fresh-run) records the parameters, full old and new identities, seven transaction hashes and replay command.

- Chromium drove a verified fresh funded C1 run. After the first 30 s checkpoint, the named manager reranged from [−120, 120) to [−180, 180) at parity at 2031 s. Simulation and actual execution used the same terms, seed ID, 100,000,000,000 L, [2030, 2040] time window, [0, 1) execution tick, 900 A/B input limits and 598 A/B output floors. Salt 1 retired and salt 2 held the entire vault position. Independent core log and key reads confirmed at most one live identity. Cooldown advanced to 2061. Idle balances moved from 1,401.826223 to 1,104.082470 of each token with zero fees on the rerange.
- The trader spent 603.584180 of the offered 700 B for 598.173776 A. The stored tick reached 120. The new position still covered the accepted band and qualified at that tick. The exported statement spanned blocks 15–30 with 19 product events and qualifying intervals of 30, 1, 59 and 90 seconds. At close, Q=180, earned and reserved compensation was 60 B, and 40 B was refundable. All 100 B stayed in escrow.
- Removal returned 297.743752 A and 1,497.690955 B principal plus 1.810752 B in fees. Actual treasury receipts including idle assets were 1,401.826222 A and 2,603.584177 B. Core liquidity and vault token balances ended at zero. The UI showed pending, mined and rejected requests. A stale position ID, wrong run/stage and invalid request credentials could not submit a rerange. Concurrent duplicate requests produced one receipt.
- TypeScript, production build, artifact bindings, browser statements and independent core/balance checks passed. Targeted payment-failure and interruption regressions passed, including the actual post-close rejection. The preserved block-27 deployment retained its run ID and head hash. Product contracts, M1, M6 and dependency pins were unchanged. The retained 115-test product result applies.
- Next have another developer perform the pinned fresh setup and reproducibility rehearsal, then prepare the final presentation. This author replay does not pass A6. A1/A2/A3 still require dated customer decisions and buyer-specific economic evidence. The measured M6 retainer comparison remains applicable.

### A6/M8 clean-checkout author rehearsal, 25 November 2026

The author rehearsed public revision `eb4922d6a344987f6b041933bb0ce34ac9c6902d` in an isolated, clean checkout on a provisioned WSL2 host. The [rehearsal record](docs/A6-AUTHOR-REHEARSAL.md) gives tool versions, actual run IDs, block anchors, transaction hashes and balances. The full dependency clone and default browser download each exceeded 180 seconds. A shallow fetch of the pinned commit and a byte-range download of the same pinned browser completed setup. The five M1 hashes, Solidity build, generated ABI comparison and TypeScript/Vite build passed.

- Each round used three funded deployments. Both manager runs closed at Q=180 with 60 B earned and reserved. Both interruption runs paused at Q=90 and closed at Q=120 with 40 B earned and reserved. Both payment runs closed at Q=180 with 40 B paid and 20 B reserved. The treasury withdrew 2,100.346049 A and 1,900.054977 B while the manager's transfer was blocked. The 40 B refund preserved the remaining 20 B for the manager, who received it after route restoration.
- Across six identities, the browser observed 52 mined action receipts, including four intended reverts, and downloaded 16 statements. Event-derived quantities matched contract reads at the displayed block. Each of five named replacements rejected the old manifest and action credentials. Rehearsal services used isolated loopback and were stopped. The historical block-27 endpoint was unavailable for live verification.
- Rehearsal evidence and setup fallbacks were published at `e3570ee4f7f3a66ff721b9881c1d908593924610` and that live development tip was verified. Subsequent reviewer instructions and status edits are documentation only. The runtime revision exercised remains `eb4922d`.
- Next obtain a dated, independent clean-checkout replay using the [developer checklist](docs/A6-REVIEWER.md), then prepare the M8 presentation. A6 remains pending. A1/A2/A3 still need customer decisions and buyer-specific economics. M6 measured matching liquidity delivery under the bounded retainer. The refund redistributes the budget.

### Viewer dependency assessment and presentation readiness, 25 November 2026

The [assessment](docs/VIEWER-DEPENDENCIES.md) records the full npm audit at published baseline `abd7c9a`, seven upstream advisories and their applicability. The checked dependency commit `a3c5173d9546d017ba322b66ea8096eabdd8ba55` pins Vite 6.4.6 and resolves both viem paths to ws 8.21.0. The full installed-tree audit returned zero entries. Vite development HMR and Playwright remote WebSocket modes still carry older bundled code. Use the built loopback preview and locally launched browser for the presentation.

- Locked installation, dependency resolution, TypeScript, production build and existing compiled ABI checks passed. The served files matched the earlier rehearsal build byte for byte. Chromium verified the manager rerange, swap interruption/recovery, blocked payment, revoked manager, independent principal receipt and protected refund. Seven downloads reconciled against the displayed blocks and contract reads. Reset, identity and duplicate-action checks passed.
- The next packaging task is the evidence-backed README, judge pitch, timed demo script and submission checklist. Independent A6 review and the recorded presentation remain pending. A1/A2/A3 remain open. M6 measured equal delivery under matched management and the refund redistributes the existing budget.

### M8 packaging progress, 25 November 2026

Published the judge README, pitch and timed demo, inspection route, evidence questions and submission checklist in `e21e30dced5636126458b474ffa26f113e8364d5`. After the push, `git ls-remote --symref origin HEAD refs/heads/main refs/heads/development` returned that full development tip and the original bootstrap main. Anonymous Git access succeeded and the judge-facing branch URL returned HTTP 200. The presentation targets patched runtime `a3c5173d9546d017ba322b66ea8096eabdd8ba55`. The two earlier clean-checkout author rounds exercised `eb4922d6a344987f6b041933bb0ce34ac9c6902d`.

- Checked the closeout figures against the receipts, including the failed 20 B claim and the actual revoked removal. The script labels the permitted rerange and the interruption as separate author runs. Its 505 spoken words at 135 words/minute plus about 46 seconds of action time give an estimated 4:30. Human rehearsal and final file timing are pending.
- Ran `python3 -B experiments/m6/check.py`. All 21 lifecycles, 45 orders and 150 receipt rows reconciled. The dedicated interrupted workload cost 9,405,354 extra gas over the matched retainer. Equal delivery and independent exit in both managed arms limit the demonstrated difference to service-based settlement.
- Verified package paths, heading anchors, revision ancestry, checkout pins, Bash syntax, UI action labels, receipt references, dedicated deployment and payer sums. The five M1 import hashes passed. Reviewed the staged scope and public content. This documentation pass used the existing 115-test product result and the recorded browser revalidation.
- **Next human actions.** A second developer completes the [A6 checklist](docs/A6-REVIEWER.md) on the patched pin. A treasury and a manager assess the same deal and provide buyer-specific cost evidence for A1/A2/A3. A presenter times the narration, records and checks a video under five minutes, and supplies the uploaded link when authorized. An authorized submitter checks signed-out access to the final materials and records the actual submission confirmation. M8 and A6 remain open. Any later integration into main needs explicit authorization for a regular merge commit preserving individual history.


### Authorized integration into main, 25 November 2026

The user explicitly authorized a regular merge, without squash or rebase. Merge `c78173c28105ed768f885a9563f6f9a15aae24b5` joins bootstrap main `e87b16b570feb0475405b0406e54096cb55bea52` and development tip `5c057fb0c4bec7b1a8bbdbb365dbbd344d2de97a`. All 44 development commits beyond the bootstrap retain their IDs, authors and timestamps. The development tip is an ancestor of the merge; its file tree matches the merge exactly. README, workflow status and submission guidance now identify main as the implemented judging branch. No product source changed, so existing runtime evidence applies. Independent A6 review, customer/economic gates, video and submission remain pending. Remote publication is verified separately after push.


### Local technical verification follow-up, 25 November 2026

Completed the remaining author-side recheck; [executed evidence and commands](docs/TECHNICAL-RECHECK.md). The unchanged product suite passed 115/115 tests. Native Linux viewer build and artifact identity checks passed, the five M1 hashes matched, and M6's published 21 lifecycles/45 orders/150 receipt rows reconciled. Fresh browser runs passed all eight statement exports and the full payment-failure, independent-exit and swap-interruption journeys, including rejection/reset/read-only checks. All four mutation runners passed: correct baselines and compiled mutants, followed by each exact intended regression failure. Removed the undeclared ripgrep prerequisite from these runners using GNU grep without changing product source or tests. Corrected stale build/closeout status and mock-token terminology, and documented that frontend onboarding begins with launcher-side acceptance/funding.

The disposable browser, raw logs and wrappers remain ignored; owned demo/browser processes were stopped. Customer acceptance, buyer economics, independent A6 review, timed video and actual submission remain pending. Next: a second developer executes A6; the presenter records/times the existing demonstrated paths while customer validation continues. These follow-up changes belong on development; no additional merge into main is authorized by this verification task. Commit and remote publication are checked after the final staged review.


### Remaining-requirements handoff, 25 November 2026

The user confirmed that the requested unfinished requirements are customer validation, buyer cost justification, independent reviewer rehearsal, demo video and final submission, and that no customer responses, independent review result or recorded demo link exists yet. These gates remain pending; additional author testing cannot close them.

Prepared the final-entry text and missing-evidence fields in [submission checklist](docs/M8-SUBMISSION.md). Updated the independent reviewer pin to verified `5b821b93c8cc5480e74a38e4afba66683fd0fca2`, which includes portable mutation runners, without rewriting historical runtime evidence. Refreshed the ignored, unsent two-role worksheet to the same revision and the executed M6 payer costs; no private responses or outreach were published. No customer acceptance, independent reproduction, measured human-video timing or submission is claimed.

Next dependencies in order: (1) a treasury and manager review the same agreement and actual cost/workload evidence; (2) a second developer records the two-round A6 result; (3) the presenter records the existing script, checks actual duration/legibility/audio and supplies the video link; (4) check the final public revision and video access, then submit the entry and retain confirmation. Reviewer/video work may proceed alongside customer discovery. If the evidence is inconclusive or unfavorable, retain that result; never convert preparation into a passed gate.

### Development refactor checkpoint, 26 November 2026

Started clean on development at live origin `192bb1c`. The [baseline map](docs/DEVELOPMENT-EVIDENCE.md) and [compiled selectors](docs/SELECTORS.md) record the starting implementation. The root suite passed 115/115, including three 256-input fuzz tests. The viewer build and artifact check passed. All five M1 hashes matched and 21 published M6 lifecycles reconciled. Each of the four isolated mutation checks passed its correct baseline, compiled the mutant and observed the intended assertion (lost interval, stolen reserve, expired removal and payment-dependent exit). Next check internal naming and function documentation, then test discovery, deployment and lifecycle tooling. Customer/economic and independent rehearsal gates remain open.

### Recovered function refactor, 27 November 2026

Live origin/development and HEAD matched `bfcd9a4`. Recovery found 42 unstaged files, an empty index and no untracked repository files. Compared the stage-two Solidity sources and tests byte-for-byte with the checked scratch copy. The 115-test process exited 0. The viewer build, artifact validation, eight browser statement exports and both browser replay commands exited 0. The four baseline mutation processes all finished with their expected assertion evidence. Public selectors and runtime lengths matched the baseline. Compilation metadata and deployment identities changed. The checked internal renames and documentation are ready for publication.

The draft randomized handler in /tmp/unison-stage3 passed 64 × 64 calls on seed 0x19112026. The /tmp/unison-operations owned-chain draft deployment completed but its public fork rehearsals failed fetching additional core storage at activation. No completed public-core lifecycle was established by those attempts. Next integrate and check test separation, then finish script entry points, operator commands, new M6 measurements and final browser checks. The scratch files and .local/verification logs remain outside publication.

Stage two published and verified at `9a2267ad853901e6a7a7777a3daedf6e4f6111f5`. The test layout now has 115 original bodies compared to the stage-two tree, equivalent after two descriptive test renames, a helper rename and whitespace. Final root compilation is underway (session 56186, /tmp/unison-final-suite.log), with discovery queued to /tmp/unison-discovery.log. The first compile found a fixture helper still private after extraction, now corrected. Next collect this exit code, rerun the four relocated mutation selections and regenerate the reader identity. Draft operator code remains in /tmp/unison-operations. Found and corrected a draft keystore path that could have used the upstream RPC during simulation; the mocked signer-routing regression passed. No public transaction was submitted.

The final separated suite and discovery exited 0: 18 unit, 94 integration, three fuzz tests at 256 inputs and one invariant campaign. Seed 0x19112026 ran 64 sequences of depth 64, with 4,096 successful handler calls, zero unexpected reverts and zero discards. Current viewer bindings and build passed. The four isolated mutation runners are queued sequentially (session 49465, /tmp/unison-final-mutations.log). Next collect the result, commit the test stage and check the deployment scripts on the final build.

All four relocated mutation runners exited 0. Each baseline and mutant compilation succeeded, followed by the exact expected test failure and required trace checks. Final assertions were OldIntervalLost(100,0), ReserveStolen(20000000,0), ExpiredPositionChanged(100000000000,0) and PrincipalReceiptShort(1900054977,1401826223). New build identity and product byte sizes are in the development evidence. Next validate deployment, ownership and real-core fork behavior.

Test stage published and verified at `da8cec7b71661052e9e019e37530d2aa5e45e35a`. The Foundry deployment and lifecycle scripts compiled. Local constructor rehearsal and the deployment driver exited 0 with 12 local receipts. Pending network stage uses scripts/ops/network.py, config/{local,sepolia,mainnet}.json and script/*.s.sol. The final Sepolia behavior run is session 78188, log /tmp/unison-final-sepolia-fork.log. Next collect that result, run the mainnet fork sequentially, and check the mainnet refusal. The earlier two incomplete fork attempts remain failures. No public broadcast.

The local and Sepolia dry-runs exited 0 with 12 and 11 owned-chain receipts. Both official-core fork behavior checks exited 0 at the configured pins, including actual activation, external swap and principal recovery. A read-only upstream relay resolved archive transport failures. The pinned nested Forge simulation rejected the Optimism hardfork name on Sepolia. Local Foundry constructor simulation passed, and on both forks the driver checked the actual direct CREATE, constructor bytes, ownership and final bindings. Mainnet preparation rejected the missing pair/reference. Simulated keystore regression passed. See docs/NETWORK-CHECKS.md. Manifests are .local/ops/recheck-local-1.json and sepolia-final-sim.json. Next collect the operator rehearsal (33814, /tmp/unison-final-operator.log), finish the Make targets, rerun browsers and measure the current M6 comparison.

### Recovery and operator verification, 27 November

Confirmed development HEAD and live origin at c795bee4fc582aa1f3b1de8ca0febdd4c800cae1, empty index, six tracked edits and eight new tooling files. The earlier owned check-actions session 33814 exited 0. Its terminal export reconciled 49,000,000 claimed, 51,000,000 refunded and zero reserved. It exercised both actors, all three position adjustments, both close paths, Foundry rehearsal and guarded failures. The earlier /tmp logs and scratch directories were absent at recovery. Persistent ignored manifests, mutation evidence and browser installation remained. npm's own full ci log recorded esbuild@0.25.12 postinstall exit 0 and npm exit 0. Its allowScripts warning named only that package. Viewer build and artifact check both passed without changing npm policy. The earlier source-inspection command's last rg returned 1 for zero shell-function matches in the mutation runners. Next check the OP Stack runtime adjustment (93134, .local/verification/final-karst-sepolia.log), then run Make/browser/M6 verification. No prior owned jobs remained running.

Operator actions published and verified at 8212652c4d1ceeebe12f6c1f85a24b3468eb2fbd. Both final Karst runtime fork checks passed on the configured official cores, as did the Sepolia Foundry constructor simulation, Sepolia preflight and both local and Sepolia Make dry-runs. Current receipt journals are .local/ops/local-final-dry.json and sepolia-karst-dry.json. The first Karst Sepolia request failed DNS and succeeded on retry. Final local verification is running sequentially in session 20436, .local/verification/final-make-check.log with a matching .exit sidecar on completion. Next collect category/browser/M6/mutation outcomes, check remaining command guards, publish the Makefile, docs, scripts/verify.py, scripts/ops/checkLocal.py and scripts/viewer/replay.py.

Karst checks published and verified at e1b588075c78d80361d2c8722e330a68c3c594c7. The separate category Make targets passed 18 unit, 94 integration, three fuzz (256 each) and one 64 × 64 invariant (all 4,096 handler calls successful, zero discards/reverts). Eight final Chromium statement downloads and both receipt journeys passed, including the blocked-manager exit and interrupted swap. Fresh M6 data in .local/ops/refactor-m6 reconciled 21 lifecycles, 45 orders and 150 receipts. The interrupted premium over the retainer is 9,405,402 gas. The historical figure was 9,405,354. The aggregate Make job 20436 continues through its remaining operator and mutation checks. Mainnet preparation and both public submission guards rejected their negative inputs before any public send.

The aggregate run passed the final root 116/116 and the operator acceptance checks through a reconciled local terminal statement. It has detected the clock and reserve mutants and is compiling the revocation mutant. A follow-up masks credential-bearing HTTP transport errors and checks that behavior in scripts/ops/checkRouting.py. The remaining browser rehearsal now includes the older read-only state and fault vectors. After session 20436 exits, run bash .local/verification/refactor-remaining.sh to check those final operator/browser files. Its release-*.log and .exit files retain individual results without publishing machine logs.

The aggregate final Make run (20436) exited 0 including both aggregate aliases, all four exact mutation failures and historical M6 reconciliation. Final source follow-up is session 27227, running .local/verification/refactor-remaining.sh. Its per-command statuses cover help, sizes, routing/redaction, both forks, generic local dry-run, extended Chromium reader coverage and the complete operator lifecycle. Next inspect release-*.exit, record final results, stage only the tooling and documentation, push development and verify the live ref.

The secret-redaction regression, source-aware size/ABI inventory, both pinned fork lifecycles and the generic local dry-run passed with the final operator provider. Full URL strings are suppressed on transport errors and failed keystore submissions. The remaining release browser and operator acceptance jobs run sequentially in 27227.

Release recovery found f80690f already committed and pushed. The original command-completion record at 10:15 UTC shows exit 0 and matching ls-remote output. The separate release script exited 1 at 10:16 UTC because the new acceptance assertion indexed the hook's named qualification result numerically. Browser exit 0 and the six prerequisite exits persisted. Corrected checkLocal.py to require qualified=true and failures=0. The transport and failed-keystore redaction checks use synthetic markers. A clean isolated build and discovery are running in session 79889, with the directory recorded in .local/verification/current-fresh-path. Next compare identities, preserve the previous generated output, and rerun only operator acceptance.

Fresh build 79889 and its source-by-source discovery comparison exited 0. The 25 product/core/fixture ABI and bytecode identities matched both .local/verification/fresh-3hZjh0oN/previous-out and the installed output. Previous generated cache/output remain privately preserved there. Corrected operator session 1872 exited 0, independently recorded in .local/verification/release-actions-corrected.exit. Its block-33 statement reconciled 153 seconds, 51,000,000 B base units claimed, 49,000,000 refunded and zero remaining rights or owned liquidity after treasury recovery. release-actions.exit still records the earlier failing named-result access. Chromium exited 0. Operator redaction and signer-routing checks passed with synthetic inputs. The final publication includes the Makefile, direct Python dependency pins, verification and replay entry points and the checked runbook. Outstanding external work is a reviewed production pair/reference, buyer/economic validation and independent A6. Public submissions and explorer verification remain unexecuted.

### Judge handoff for the verified development implementation

The implementation and A6 checkout pin is `e14fb19801c9c3bede31b36d9cfeb2ad237c66f2`, verified on local and remote development before this documentation change. The retained root execution passed 116 tests in 16 suites. Fresh discovery independently matched the 116 names and paths. The four mutation, browser, operator and pinned-fork results are recorded in the [development evidence](docs/DEVELOPMENT-EVIDENCE.md). The two interrupted M6 receipt tables reconcile to a premium of 9,405,402 gas on this build and 9,405,354 on the historical build. The operator’s 153 seconds earned 51 B. The separate blocked-payment script earned 60 B in 180 seconds and retained 20 B through refund. The [judge handoff](docs/M8-SUBMISSION.md#judge-handoff) gives the setup, three-minute route and outstanding actions. Next obtain buyer decisions and cost evidence, independent A6 results, a timed video and authorized submission confirmation. Mainnet still lacks reviewed production token and reference configuration.


### Conventional Foundry dependency layout, 27 November 2026

Authorized by the user's request to structure Unison like the POINCARE example. Active builds now use root `lib/v4-core`, `lib/solmate`, `lib/forge-std` and `lib/openzeppelin-contracts`, all pinned Git submodules with official public URLs, and root `remappings.txt`. Root Foundry discovery, operator manifests, mutation sandboxes, Make setup and active runbooks now use these paths. No competitor implementation, product-contract change or library upgrade was introduced. Preserved M1 sources/configuration/hashes/vendor checkout remain untouched. `make init` restores active dependencies; `make prerequisites` verifies their pins. The historical A6 pin must use its own checkout instructions.

The [layout recheck](docs/DEVELOPMENT-EVIDENCE.md#standard-foundry-layout-recheck) records 116 passing tests, unchanged ABI/selectors/runtime sizes for 31 compared declarations, all four intended mutation detections, fresh operator recovery, eight browser statement exports, viewer build and 21 reconciled M6 lifecycles. New comparison tables are public under `experiments/m6/results-layout-2026-11-27`; the new interrupted premium is 9,405,390 gas. Metadata/build identities changed and generated viewer bindings were regenerated. Old deployment manifests cannot be reused. No deployment or fresh public-network fork campaign occurred. Independent/customer/economic gates and video/submission remain open. Publish the checked change to development; this new layout has no additional main-merge authorization.

### Foundry network and operator suite, 27 November 2026

Started with a clean index and worktree on development at live origin `12f8685c94a5317684c8ce66059e6141bcedcb04`. Confirmed both configured core addresses against the official Uniswap v4 deployment and Unichain contract tables. The vault captures the direct CREATE sender and creation timestamp. Deployment must finish on an unaccepted revision and read the actual mined terms hash back before use. Next compile explicit network workflows, exercise their records against mined local transactions, then exercise typed actions, closeouts and pinned forks. No public execution or main merge authorized.

Stage check: all three network entry points and the interaction sources compiled with pinned solc 0.8.26. The first compiled deployment exceeded the compiler's Yul stack capacity; splitting hook installation and reusing the constructor-created OpeningQuote resolved it. The first local execution needed read permission for out/ artifacts. The corrected DeployLocal run produced ten mined transactions, passed direct CREATE/CREATE2/runtime checks, and VerifyDeployment returned the mined revision-two terms and empty position. Evidence: ignored .local/ops/forge-smoke-2jm9mca4/test.json and per-invocation Forge journals. Next reconcile both script-driven terminal paths, exercise rejected inputs and pinned public cores, then publish the checked development changes.

The first complete local early-close and expiry runs reconciled manager payments of 36,333,333 and 96,000,000 B base units respectively. Early close preserved 7,333,333 through principal recovery and refund while compensation was blocked. The first action receipt importer expected run-latest.json for every operation; named Forge functions use their own *-latest.json. Corrected discovery and replayed both full paths. Deployment stage committed locally as f207056. Next check the fresh Make rehearsals including the separately mined failed payment, unfunded cancellation, fixture refresh, both fork pins and external-dependency mainnet negatives; then check the legacy reader, document the verified commands and push development.

### Foundry recovery, 28 November 2026

Recovered development HEAD f207056e5b16d0a34978335570d30331dce6f662, one commit ahead of live origin/development 12f8685c94a5317684c8ce66059e6141bcedcb04. Index empty, eight tracked edits and eight untracked implementation/runbook files. No surviving owned jobs. Earlier process exit handles and /tmp smoke runner are unavailable. Its persistent loopback smoke outputs include a verified draft and mined accept. The final local log and journals contain both reconciled terminal balances and cancellation, and the legacy log contains its completed block-33 reconciliation. Their original shell exit codes were not recovered.

The first failing operation in forge-mainnet-final.log was the upstream relay's eth_chainId read (ReadTimeout) after successful compilation. Anvil exited during startup, before core or production-config checks. The Sepolia retry similarly failed eth_chainId with ConnectionError; an earlier nine-deployment-receipt Sepolia rehearsal completed settlement. The older mainnet-suite failure reached previewOpening and rejected an aged fixture observation. Keep all three logs. Next collect the same-pin mainnet retry in .local/verification/forge-mainnet-recovery-28.{log,exit}, recheck the Sepolia pin if needed, reconcile preserved onchain evidence, finish the operations handoff, commit and verify the authorized push.

The mainnet retry at block 64985000 exited 0. DeployUnichainMainnet produced six owned-fork receipts with externally supplied stand-ins and the pinned official core. The lifecycle reconciled 287 qualifying seconds, 95,666,666 B paid, 4,333,334 B refunded and both principal receipts. Separate empty-production-config, wrong-code, reversed-pair and stale-reference checks rejected their inputs before a nonce changed. Nine new script entry points compile, every new Solidity function has preceding NatSpec, all product selectors and viewer artifact identities match, and signer-routing/redaction checks pass. Next finish the Sepolia retry, check the public-safe receipt inventory and verify the development push.

Both corrected pinned forks exited 0 with the original core hashes and blocks. The separate unsent fork checks exited 0 with zero receipts and unchanged nonces: Sepolia produced a simulation, mainnet rejected its incomplete checked-in production configuration. The [operations evidence](docs/FOUNDRY-OPERATIONS.md#executed-script-evidence-2728-november-2026) and [receipt inventory](docs/FOUNDRY-RECEIPTS.csv) cover 47 deployment transactions, 66 typed actions and 36 fixture transactions on owned chains. Receipt event recipients and amounts matched the independently measured balances. The deliberately failed local claim is the only status-zero receipt. All requested .s.sol files have execution evidence. The separate current-head public preflight with an unfunded disposable address stopped at the OP fee check. Public signing, submission and explorer verification remain unexecuted.

Published f207056 and 0c9491e to development and verified the latter's full ID 0c9491e483e8a557ac4da046b94b0abfb4321fc0 via live ls-remote. Next publish this checked evidence commit and verify its remote ref. Remaining external work is the reviewed mainnet configuration, customer/economic decisions and independent A6 rehearsal. Main and product contracts were outside this change.

### Safe and wallet lifecycle inspection, 28 November 2026

Reviewed clean development at `5c3cfc990e1cf3544b313547adc3296f3e5d6806` and verified its publication at live origin/development. The [requirements and acceptance criteria](docs/DEVELOPMENT-EVIDENCE.md#safe-and-wallet-lifecycle-checklist) extend the existing C1 evidence map. Installed product/reader artifacts, dependency pins, layout M6 data and all 149 recorded receipt hashes/statuses matched their respective records. The five Foundry manifests identify dirty `f207056` builds with matching recorded Solidity inputs. The final offchain runner still lacks an exact clean-tip full replay. The recorded local regression and closeout evidence supports proceeding to the actor decision.

Next decide how the named treasury becomes the immutable vault treasury for both an ordinary wallet and a Safe. Specify caller, constructor and receipt provenance, independent acceptance and the authority to recover principal. The local threshold-Safe proof follows that decision. Trade preview, separate invoice verification, wallet onboarding and readable approvals remain planned. The real reference depends on a reviewed pair. Customer acceptance, buyer economics, independent review and A6 rehearsal remain pending. This documentation change is scoped to the authorized development publication.

### Treasury ownership and deployment decision

Reviewed clean development at `8b398f0401a4e8e0814a9c565e8505413bd26db0` and confirmed the inspection commit on live origin/development. The [ownership decision](docs/DEVELOPMENT-EVIDENCE.md#treasury-creation-and-transaction-preparation) selects direct EOA vault creation and a real 2-of-3 SafeL2 v1.4.1 delegating the exact vault CREATE to official CreateCall in the proxy's context. Both paths use the existing constructor and fixed beneficiaries. The [transaction package](docs/DEVELOPMENT-EVIDENCE.md#approval-package-and-browser-boundary) uses chain/vault identity, separates executor and Safe nonces, and requires canonical receipts, Safe outcome and product effects.

Read-only checks matched the three official Safe infrastructure runtimes at the configured Unichain Sepolia block, and the installed product and viewer artifacts passed their checks. Safe execution remains unverified. Next implement only the [local ownership proof](docs/DEVELOPMENT-EVIDENCE.md#implementation-acceptance) with pinned artifacts, two genuine owner signatures and an independent executor. Require the creation/success logs, revision-one terms and correct treasury, plus rejected direct-owner revision, before extending through the full lifecycle. Customer/economic gates and independent review remain open. Publication scope is the two planning documents on development.
