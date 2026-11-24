# Unison implementation plan

## Scope and current state

One treasury, one manager, one token pair, one fixed-fee Uniswap v4 pool, one active position, one fixed period and a separate compensation budget. Treasury owns principal, idle assets and LP fees. Compensation purchases agreed service, not profit or manager effort.

M1 passed the isolated compatibility/accounting experiment. M2 covers bounded management and independent principal recovery on a local chain with mock assets. M3 service-time accounting passed the local C1 engineering criteria. M4 earned compensation, reserves and terminal refunds passed the local C1 engineering criteria. M5 closeout passed the local C1 engineering review. M6–M8 remain open. M0 candidate C1 is specified. Customer acceptance and preliminary economic justification remain pending. The user authorizes a narrow experimental hackathon MVP on a local chain with mock assets while A1 and preliminary A2/A3 continue in parallel. Technical completion establishes neither customer acceptance, product-market fit nor economic advantage. Real-fund use and public deployment are outside this decision. Project ID supplied by the user: HK-UHI11-1275.

Read only the next milestone, its applicable gates and relevant source/evidence. Older recurring-epoch proposals are superseded by this single-period plan. Missing feedback stays pending; a deadline or commit target cannot pass a gate.

## Six acceptance requirements and build gates

### A1. Customer and service fit — M0

Obtain dated feedback from at least one prospective treasury operator and one manager on the SAME exact candidate agreement: purchased service, passive delivery, market/inventory risk, payment, early termination and costs. Record role, objections, terms revision and permission for attribution. Interviews/form responses expressing interest alone are not acceptance or product-market fit.

**Pass:** both roles understand and accept the narrow agreement for a stated use case. If they need profit or continuously market-relative depth, revise the service before dependent full-product work. Public case studies establish a problem category, not acceptance of this metric.

**Status:** pending. A research form exists; no accepted customer terms or responses have been verified here.

### A2. Credible simpler comparison — M0 preliminary, M6 final

Compare passive liquidity/owner exit; bounded management with time-prorated retainer/simple escrow; and identical management with Unison service pay. Include an observer plus programmable settlement where it is a credible alternative. Match inventory, funded compensation, duration, fee settings and incoming order intentions. Allow fills/prices to differ when liquidity differs.

**Pass:** reproducible results show a useful service/reconciliation/closeout advantage for the stated buyer, including negative cases. Lower manager pay alone creates no new joint economic value. Record preliminary comparison feasibility and a defensible reason to test while the local experiment proceeds. Final comparison uses the complete lifecycle.

**Status:** partial M1 accounting evidence; no demonstrated complete-workflow superiority.

### A3. Justified total cost — M0/M1 preliminary, M6 final

Measure comparable no-hook/hooked active, repeated and ended swap paths; deployment, management, claim, refund and exit. Include operator effort, monitoring, security review, tied-up capital, failed transactions and who bears each cost, including traders. Declare workload, gas-price assumptions, instrumentation and exclusions.

**Pass:** the buyer-specific benefit justifies total added cost. No universal gas threshold; an inconclusive or unfavorable benchmark is not a pass. Recheck provisional economics against final workflow measurements.

**Status:** partial. Controlled M1 swap increments: 97,462 outward, 57,636 return and 26,904 after termination. These are diagnostic samples, not a typical average or full transaction-cost estimate. The pool cannot detach its hook after termination.

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

**Pass:** another developer reproduces pinned setup; two fresh reset runs match state and balances. Label mock tokens, accelerated time, estimates and known limits. Use actual transactions, not chart changes. Full journey remains pending.

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

**Exit:** 100 six-decimal USDC × 180/300 = 60,000,000 units; one second = 333,333 units. Claims/refunds/earned reserves conserve funds. Expose terms, qualification reasons, seconds, earned/claimed/reserved/refundable amounts and reconstructible transition events.

**Frontend:** begin thin real read-only UI when these interfaces stabilize. No per-second transactions or mandatory indexer/database.

## Priority 5 / M5: prove complete closeout under failure

**Complete for the local C1 engineering experiment.** The [closeout review and evidence](docs/CLOSEOUT.md) maps all product writes, terminal rights, failure assumptions and targeted mutations.

**Depends:** M4. Termination checkpoints, freezes entitlement and revokes authority without transferring compensation. Keep pull-claim, unearned refund, liquidity removal and principal receipt separately callable. Natural expiry disables management even without a transaction at the exact deadline.

**Exit:** A4 passes for early termination, expiry, cancellation, repeated calls, delayed transactions and residual assets. Prove a manager-specific payment failure, independent principal receipt, then restored manager claim. Exit returns current assets, not guaranteed original quantities/value.

## Priority 6 / M6: prove what Unison improves

**Depends:** M5 for final evidence. Recheck A2/A3 using full lifecycle. Include passive flat case, feasible recovery, unavailable inventory, delayed execution and external-price drift. Record native LP fees, service, compensation, inventory, marked value, slippage, capital/opportunity costs and gas separately.

**Exit:** A5 detects selected defects; final buyer-specific economic comparison supports the claim. Keep unfavorable/inconclusive outcomes; revise if the simpler alternative wins.

## Priority 7 / M7: finish one usable judge page

Thin reads start after M4; tested writes connect as M5 paths stabilize. Polish after M6.
- One agreement page: accepted terms, owner/manager roles, separate balances, qualification/reasons, earned/paid/unpaid/refundable, supported actions and closeout statement.
- Reconstruct payment from events/initial state; contract entitlement remains authoritative. Export a readable statement and JSON with terms, interval/block coverage, balances, obligations and transaction references. Report incomplete data.
- Distinguish claimable/refundable from actually transferred funds. Explain nonqualification without assigning manager blame.
- Generate ABIs/addresses; handle account/network mismatch, pending/revert/read failure and stale reset state.
- Local scenario controls execute real swaps/time advances under R8. Supported plain mock ERC20s only initially.
- Safe ownership is optional after core correctness; suitable opening-reference adapter is conditional. Simulation and professional manager adapters are deferrable.

**Exit:** a user completes the actual flow without terminal work, can inspect why pay changed and can exit despite manager compensation failure. No simulated success screen substitutes for enforcement.

## Priority 8 / M8: package, rehearse and submit

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
- Latest documentation review: 24 November 2026. Historical evidence dates are preserved. Research form prepared/published; no customer acceptance inferred.
- Next run the M6 matched comparison and cost measurement across the full lifecycle. The unchanged M4 read interfaces are eligible for a thin read-only frontend. Customer validation and reproducible demonstration remain open.
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

- First local M2 slice. Published the [acceptance implementation](src/AgreementVault.sol), [tests](test/AgreementVaultAcceptance.t.sol) and canonical C1 field list together at `9aaa170` on `origin/development`. The vault commits to the exact candidate numerical schedule, roles and fixed recipients, full pool/custody identities and opening rules. Revisions clear both approvals even when restoring previous bindings. A live observation, derived ticks and start time belong to future activation.
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
