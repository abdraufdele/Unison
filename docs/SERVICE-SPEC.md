# Candidate liquidity service agreement

**Revision C1 · 23 November 2026 · for treasury and manager review.** All values, permissions and interfaces below are proposed terms. Neither role has accepted C1. The mock example gives both reviewers the same quantities and decisions to evaluate. The governing gates are in the [implementation plan](../PLAN.md).

## Buyer, service and asset rights

A treasury operator has inventory in two tokens and wants traders to find liquidity near an agreed opening price during a fixed window. The treasury buys seconds in which its identifiable position supplies a minimum amount of liquidity, covers the opening band and can trade at the current pool tick. An unattended qualifying position earns the same rate as one the manager actively maintains. Trading away from the position can interrupt pay even when the manager followed the agreement.

| Asset or right | Holder and destination |
| --- | --- |
| Deposited pair, idle balances, liquidity and native LP fees | Treasury bears price, inventory and execution risk. AgreementVault owns the core position for the treasury. All proceeds of pool operations settle to the vault. All withdrawals go in kind to the fixed treasury recipient. |
| Service budget | Treasury funds CompensationEscrow separately. The fixed manager recipient can receive earned compensation. The fixed treasury recipient can receive the final unearned remainder. Neither role can redirect a transfer. |
| Manager authority | One named operator may adjust one position within the limits below. The manager has no title to vault assets, LP fees or unused budget. |

Each caller pays its transaction gas. C1 assumes the treasury submits setup and exit, the manager submits adjustments and its claim, and traders pay their swap costs. There is no gas reimbursement from either custody account. Early termination can leave the manager with unrecovered operating costs.

The service excludes profit, trade volume, execution priority, continuous depth at an external market price and any obligation to submit a minimum number of transactions. Same-timestamp liquidity can capture LP fees while earning zero additional service seconds. The MVP excludes shares, a project token, multiple mandates, a marketplace, AI management, multichain operation, renewal and a generic executor.

## C1 terms sheet

| Term | Candidate and reason |
| --- | --- |
| Parties and settlement | One treasury address also receives all principal, fees and refunds. One distinct manager address also receives all compensation. Fix both for the life of the agreement to make the beneficiary of each transfer checkable. |
| Pair and pool | Local plain mock ERC-20 A and B, 6 decimals each, with A ordered as currency0 and B as currency1. One initialized v4 pool, static fee 3,000 millionths (0.30%), spacing 60, one ServiceHook. Bind chain ID, PoolManager and complete PoolKey. This gives one price convention and one fee schedule. |
| Inventory and price | Treasury supplies exactly 2,000 A and 2,000 B. Opening reference fixture is 1 B per A with 8 feed decimals. Equal denominations make the depth example inspectable. Token B also denominates pay, exercising same-token custody separation. |
| Window and budget | One 300-second period, budget 100 B (100,000,000 base units). Accelerated review fixture using the plan's payment example. Start is the successful activation timestamp. Fix the activation cutoff at draft creation time plus 24 hours, leaving time for separate acceptances and funding. |
| Range and depth | Opening price ±1% before outward grid rounding. Minimum qualifying liquidity 100,000,000,000 raw L. Seed exactly that L at the band. Cap position L at 200,000,000,000. One grid interval is too coarse to express exactly 1% at both ends. The wider aligned band and example below make the actual coverage visible. |
| Management limits | Maximum range width 480 ticks. Each edge may extend at most 120 ticks beyond its band edge. At most one successful manager operation per 30 seconds, giving time to observe an adjustment in the fixture. A manager's execution window lasts at most 30 seconds. |

A concrete agreement must fill all address slots (including vault, hook, escrow, token contracts and opening adapter), actual pool identity, creation time, cutoff and revision before either party accepts. A fixture label is sufficient for this review. It cannot identify an asset in a live agreement. C1 assumes immutable contracts, a dedicated vault and escrow, ordinary exact-transfer non-rebasing tokens and no token callbacks. Deposits and payouts must reconcile actual debit and receipt exactly or revert.

## Opening reference and purchased depth

At activation read the accepted adapter once. Bind its pair, orientation, decimals and source in the terms. Require a valid completed positive observation, timestamp greater than zero, no future timestamp and age at most 60 seconds. Reject unreadable data, a mismatched pair or scale, and values outside representable pool bounds. A local fixture can publish a fresh mock observation. Selecting a real source and justifying its freshness remain open.

1. Interpret the feed answer as an exact rational human price in whole B per whole A. Require that orientation for C1. Convert to a raw currency1/currency0 price by multiplying by `10^decimals1 / 10^decimals0`. Reject reversed metadata. Retain rational precision through both band comparisons.
2. Compute the raw lower and upper prices as `99 × price / 100` and `101 × price / 100`. For a grid tick t use the price convention `1.0001^t`. Choose the **greatest** valid multiple of spacing whose price is at most the lower price, and the **least** valid multiple whose price is at least the upper price. An exact boundary stays on its tick. Reject an unrepresentable edge or an empty or over-width band. These inequalities define the result, including for negative ticks. A future integer implementation must match them at grid boundaries.
3. At the fixture price of 1, the unrounded tick bounds are approximately −100.508 and 99.508. The agreed band is **[−120, 120)**. Require the actual core tick inside the band for activation. Store the observation, normalized price and grid edges permanently. All later checks use the stored band and actual pool state.

At tick 0 the seed needs about 598.174 of each token, within the inventory caps. For scale, assume only the seed liquidity, no protocol fee and a 100 B exact-input trade at price 1. After the fixed LP fee, 99.7 B enters the price calculation. With L expressed in whole-token units here as 100,000, output is approximately `100,000 × 99.7 / (100,000 + 99.7) = 99.601 A`. The ending price is approximately 1.001995 B/A, inside the band. This is an illustrative within-range calculation. Actual fills depend on pool state and integer rounding. Validate depth against the buyer's trade sizes, inventory and fee tolerance.

## Acceptance, custody and state transitions

The vault exposes a canonical terms hash over an unambiguous typed encoding of the agreement domain (chain, vault and agreement ID), revision, parties, recipients, complete pool and custody identities, asset metadata, all quantities, timing rules, adapter, band derivation and operation rules. Include a rules-version identifier covering the fixed calculation and closeout semantics. Both named callers explicitly accept that exact hash onchain. Commissioning a document or submitting review feedback does not execute acceptance.

### What the parties accept in the local C1 component

| Commitment | Fields and interpretation |
| --- | --- |
| Domain and revision | A schema tag, creation chain ID, vault address, nonzero agreement ID, revision (starting at 1) and draft creation time identify this proposal. Only the revision changes on an edit. |
| Parties and fixed recipients | The original treasury creates the vault and names the manager. Both are fixed for the life of this agreement. The treasury is the principal, fee and refund recipient. The manager is the compensation recipient. Each must call on its own behalf, including the treasury after creation. |
| Pool, tokens and custody | Commit the PoolManager, ordered ERC-20 addresses A and B, hook, fixed fee 3,000 and tick spacing 60 (the complete PoolKey with the two currencies). Both tokens have six declared decimals. Principal custody is the vault. The separate escrow holds B as the payment token. |
| Inventory, budget and time | In base units commit 2,000,000,000 of each principal token and 100,000,000 of B for pay, a duration of 300 seconds, and cutoff at creation + 86,400 seconds, exclusive. |
| Opening reference | Commit the adapter and its named source address, A as base and B as quote, eight answer decimals, 60-second maximum age and a 100-basis-point half-band. The opening-reference rules bind rational conversion, valid timestamps and outward grid rounding. |
| Liquidity and operation limits | Seed and minimum L are 100,000,000,000, maximum L is 200,000,000,000. Maximum width is 480 ticks and maximum extension is 120 ticks per edge. Each gross added leg is capped at 2,000,000,000 units per currency. First and subsequent adjustments observe a 30-second cooldown. Execution windows last at most 30 seconds. The rules bind the execution tick envelope, caller-tightened bounds and position identity. |
| Rules version | The identifier for C1 version 1 binds the qualification, custody, management, acceptance, payment, rounding, revocation and closeout semantics in this specification. Accepting those rules records consent. Later milestones must implement and test them. |

For this slice the treasury may revise the pool, token, hook, escrow and reference addresses. The numerical schedule is the exact candidate above, exposed as typed values. Recipient and payment-token fields are derived from the fixed roles and ordered pair. The component accepts no independent recipient overrides. The source is identified by an address as a local implementation choice. Selection and verification of an actual source remain open. The local component requires nonzero addresses, distinct parties, tokens and pool/custody contracts, and A ordered before B by address. Adapter and source can coincide.

The commitment is `keccak256(abi.encode(TERMS_SCHEMA, currentTerms()))`. The schema tag is the Keccak-256 of the ASCII string `Unison.AgreementVault.Terms.v1`, and the rules identifier uses `Unison.C1.Rules.v1`. The Solidity return tuple defines the field order and integer widths for independent encoding. Each accepted-revision record is zero until its role accepts. At cutoff the records still describe the parties' decisions, while the acceptance and revision windows are closed.

At acceptance the actual observation, normalized opening price, derived band, seed position identity, actual start and scheduled end are unavailable. At activation the vault must verify the accepted identities and metadata, validate the fresh observation, compute the band under the accepted grid rules, check the pool tick, then seed successfully. Only that transaction fixes the start and the end at start + duration. The example price of 1 B per A is a fixture input. Address validation during acceptance cannot establish deployed wiring, oracle validity, token transfer behavior or seed feasibility.

The local component currently exposes only Draft and Accepted. At funding integration, the vault must check the hash, both current acceptance records, treasury caller and cutoff, credit exact deposits atomically, then close the revision path on funding. The present tests cover consent only. [Acceptance component](../src/AgreementVault.sol)

### Lifecycle transitions

| From | Action and guard | Result |
| --- | --- | --- |
| Draft | Either named party accepts the current hash before cutoff | One acceptance leaves Draft. Both matching acceptances yield Accepted. Repeating the same acceptance changes no rights. |
| Draft or Accepted | Treasury revises before funding and before cutoff | Increment revision, clear **both** acceptances and return to Draft, even if fields later revert to old values. The original treasury controller, agreement domain and creation-based cutoff stay fixed. |
| Accepted | Treasury funds before cutoff | One atomic call deposits the exact two principal amounts to the vault and the full budget to escrow. Credit funded rights once. Any short receipt or failure rolls all three back. State becomes Funded. |
| Funded | Treasury activates once before cutoff | Recheck both current acceptances, credited and available funds, pool configuration, fresh opening reference, execution tick and seed feasibility. Atomically establish the band, open the seed and initialize the clock from actual state. Enter Active. Failure leaves Funded, cancellable and retryable before cutoff. |
| Draft, Accepted or Funded | Treasury cancels at any time before activation. Anyone may cancel an unactivated agreement at or after cutoff. | Cancelled. No accrual. Only credited funds create refund rights. Any deposited principal is withdrawable separately. At the cutoff acceptance, edits, funding and activation are already disabled. |
| Active, before end | Treasury terminates | Terminated at execution timestamp. Checkpoint through that instant and revoke manager authority in the same call. |
| Active, at or after end | Time reaches start + 300 | Effective state is Expired immediately. Anyone can persist the final checkpoint later. Management always checks time. A late close records expiry at the scheduled end. |
| Cancelled, Terminated or Expired | Exercise an outstanding right | End reason persists. Claims, refund, liquidity removal and withdrawal settle independently. No terminal transition requires a successful payment. |

There is no edit after funding and no second activation, replacement manager or renewal. Termination takes effect in chain order. A valid manager action ordered before termination can execute. Later actions fail even in the same block.

## Manager permissions and position identity

Only the named manager, while Active and before end, may call the vault to **add**, **remove**, or atomically **rerange**. Inputs reference the expected current position identity (or empty identity for reopening), current terms hash, validity timestamps and the requested liquidity change. The interface below groups the hash, execution window, tick interval and per-leg token limits in `bounds`. The vault enforces all of the following at execution.

- Fix the PoolManager, full pool key, fee, hook, vault owner and settlement recipients. A live identity consists of pool ID, vault address, lower tick, upper tick and vault-assigned salt. Allocate a fresh monotone salt on every opening, including reopening at old ticks. Add/remove in place uses the current salt. Full removal retires it. At most one identity has positive L.
- Each new or enlarged position must cover the whole fixed band. Its lower edge lies in `[bandLower − 120, bandLower]` and upper edge in `[bandUpper, bandUpper + 120]`. Both must be usable aligned ticks in core bounds, with positive width at most 480. Opening from empty requires explicit ticks. A positive post-operation L may be below the service minimum and then earns zero until it recovers.
- Add a positive L within the position cap. Remove a positive amount up to actual L. Rerange removes the entire old L and opens positive L within the same cap at different valid ticks. A manager may leave the vault empty, stopping qualification until a permitted reopening. Settle core deltas atomically. Reject if new inventory is infeasible, preserving the old position, clock and cooldown. Use only vault inventory, including proceeds of that same operation. Per added leg, gross principal spent is capped at 2,000 of each token, even if fees offset the net debit. Enforce the manager's possibly tighter per-token maximum inputs and minimum principal outputs on their respective legs. Account separately for LP fees.
- Require the actual pre-operation pool tick in `[bandLower − 120, bandUpper + 120)` and inside a caller-specified subinterval of that envelope. Bind `validFrom <= now <= deadline` with `deadline − validFrom <= 30 seconds` and reject reversed windows. Add/remove cannot move the pool price by trading. Apply these checks once to an atomic rerange. First manager change is allowed at start + 30 seconds, then at least 30 seconds after each successful change. Treasury seeding and terminal exit have separate entry points.
- The vault settles only with the fixed core and back to itself. The manager cannot select recipients, approve spenders, route assets, swap inventory, donate, borrow, call arbitrary targets, delegatecall, upgrade, change owners, accept for the treasury or withdraw proceeds. Only the treasury can initiate pre-cutoff cancellation, activation, early termination and principal exit.

The hook authenticates the configured PoolManager on every callback. The candidate pool admits liquidity additions only from this vault. For add admission the hook also validates the vault sender, expected pool/position parameters and a single-use active vault operation context matching kind and leg. For afterSwap, authenticate the configured pool and current agreement context, including independent traders' swaps. With no live clock (before activation or after close), a configured-pool swap adds no service and requires no managing caller. A trader supplies no authoritative position or timing data. Never use tx.origin. The vault directly owns the core position and explicitly checkpoints its liquidity changes. Fees from the position always accrue to the treasury.

## Service clock and funded payment

Qualification requires the active time window, the configured fixed-fee pool, an installed live identity matching actual core state, actual L at least the minimum, full band coverage within the permitted widths, and the core's current tick in **[positionLower, positionUpper)**. For an extended range, a tick outside the opening band can still qualify while the position covers the entire band and remains in range. Expose each failed predicate. Empty, retired and unrelated positions contribute zero. Price drift and threshold crossings can interrupt or sustain pay independently of manager effort.

Initialize the timestamp and qualification after seeding. At each observed swap transition or vault liquidity change, credit elapsed time using the **stored old qualification**. Clip the interval to activation and the earlier of scheduled end and termination. Then install actual new tick, identity and L. For liquidity changes the vault checkpoints before mutation and refreshes afterward, including both legs of a rerange within one transaction. For third-party swaps the authenticated afterSwap checkpoints the old interval before refreshing from core. Same-timestamp changes add zero seconds. A read projects the open interval under the same clipping rule. A claim or finalization checkpoints it once. No per-second transaction, oracle read, token transfer or unbounded scan belongs on the swap path.

Let F be credited funding (zero until successful funding), B the budget, D the original duration, Q cumulative qualifying seconds, C successful cumulative claims and R successful cumulative refunds. Use base units and full-precision integer multiplication/division, with a single floor on cumulative entitlement.

~~~text
0 <= Q <= D                 F = B for any activated agreement
E = floor(B * Q / D)        E = 0 before activation or on cancellation
claimable = E - C           earned unpaid reserve = E - C
refundable = F - E - R      only when terminal, otherwise 0
accounted escrow = F - C - R
~~~

Anyone may trigger a claim while active or after close, and a refund only after close. In those states each pull pays the full positive amount due to its fixed recipient. An eligible pull with zero due returns zero. Reverts leave counters and obligations intact. Serialize settlement against reentry and commit counters only with a successful exact transfer. At all times `0 <= C <= E <= F` and `0 <= R <= F − E`. At close, accounted escrow equals earned unpaid reserve plus remaining refund. Refunds can never consume the reserve. Surplus sent directly to escrow creates no funded rights and is excluded from payouts, with no surplus sweep in C1. Direct gifts of pair tokens to the vault are treasury-owned idle assets and cannot satisfy a required deposit.

## Closeout and proposed contract surface

Termination and expiry freeze E using the original D. Neither requires a manager call, fresh reference, compensation payment, refund or core liquidity removal. Vault exit can recognize expiry locally at end even before a keeper finalizes it. After close, the treasury can separately remove all remaining liquidity into the vault, collect treasury LP fees and withdraw idle assets to itself. It may withdraw existing idle balances before removal and call again for subsequent proceeds. These actions ignore manager price, range, cooldown, deadline and service thresholds. No exit step calls the escrow or the adapter. Receipt is of current token quantities and depends on working vault/core contracts, transferable principal tokens, chain inclusion and settlement. A globally frozen principal token can prevent its own receipt.

| Proposed owner of state | Entry points and observable results |
| --- | --- |
| AgreementVault | `revise(terms)`, `accept(hash)`, `fund(hash)`, `activate(hash)`, `cancel()`, `terminate()`, `finalizeExpiry()`. Validate the transitions above. Expose hash/revision, acceptances, credited deposits, parties, cutoff, start, scheduled end, effective stop and end reason. |
| AgreementVault | `add(expectedId, ticks, L, bounds)`, `remove(expectedId, L, bounds)`, `rerange(expectedId, ticks, L, bounds)`, `exitLiquidity()`, `withdrawIdle()`. Expose actual position, salt, balances and last successful adjustment. Bringing proceeds into the vault never pays the manager. |
| ServiceHook | Authenticated `beforeAddLiquidity` admission and `afterSwap` observation. Vault-only initialization, pre-change checkpoint, post-change refresh and stop. Expose band, active identity, observed tick and L, qualification reasons, timestamp, cumulative seconds and the clipped as-of-now projection. Ended callbacks cannot restart the clock. |
| CompensationEscrow | Vault-coordinated single budget deposit. `claim()` reads checkpointed entitlement, `refund()` reads terminal entitlement, both through the agreed clock/lifecycle. Expose F, E, C, R, reserve, claimable and refundable. Finalizing expiry records time without attempting a transfer. |

Emit revision/hash, role acceptances, funding receipts, activation observation/band/seed, position changes and checkpoint transitions (old/new qualification, timestamp, identity, tick, L and Q), effective terminal time/reason, successful claims/refunds and vault removals/receipts with token amounts. A reader can reconstruct intervals and distinguish a right from a successful transfer. Reject stale terms/identity, wrong caller/context, closed window, incomplete funding, invalid reference, invalid ticks, bounds/cooldown violation, insufficient inventory and nonterminal refund with distinguishable errors. For an already terminal agreement, repeating its close action has no financial effect. Empty terminal exits pay zero.

## Worked settlement examples

Each row is a separate funded C1 agreement with start at elapsed second 0. Amounts in the table are whole B. Service intervals include their left endpoint and exclude their right endpoint.

| Case | Clock and action | Earned | Already claimed | Final unpaid reserve | Final refund due before refund transfer |
| --- | --- | ---: | ---: | ---: | ---: |
| Full passive service | Seed qualifies throughout [0, 300). First close at 350 clips to 300. | 100 | 0 | 100 | 0 |
| Interrupted service | [0, 90) qualifies. A third-party swap takes the tick to the upper edge at 90. A return swap at 210 restores qualification through 300. Q = 90 + 90 = 180. | 60 | 0 | 60 | 40 |
| Early termination | Qualifies continuously until treasury terminates at 120. Q = 120, D stays 300. A subsequent swap adds zero. | 40 | 0 | 40 | 60 |
| Previous claim | Manager receives 40 at second 120. Service continues until termination at 180. Escrow holds 60. | 60 | 40 | 20 | 40 |
| Recipient transfer failure | 40 already paid at second 120. While still active at 180 an attempted claim of 20 reverts because B rejects transfers to the manager. Treasury then terminates at the same timestamp. | 60 | 40 | 20 | 40 |

In the failure case the treasury removes the position and receives A, B and LP fees at its own working address, even while the manager transfer fails. A successful refund of 40 leaves exactly 20 in escrow. Restoring transfers to the manager permits its unchanged claim of 20. Escrow then holds zero, C = 60, R = 40, and repeated pulls return zero. If the refund itself fails, R stays zero and principal receipt remains available. This is a required future failure test.

One qualifying second earns `floor(100,000,000 / 300) = 333,333` units. If claimed then, a claim at three qualifying seconds pays `1,000,000 − 333,333 = 666,667` units. Three one-second checkpoints still earn 1,000,000 in total. At Q = 0 a terminal funded agreement refunds 100 B. Cancelling before funding refunds zero. Cancelling after funding returns all 100 B through escrow and leaves 2,000 A and 2,000 B separately withdrawable from the vault.

## Decisions and evidence still needed

- **A1, buyer and manager.** Review C1 unchanged with both roles for one stated use case. Ask each to explain passive pay, the extended-range rule, external drift, discontinuous pay at the tick/L thresholds, early revocation and who bears inventory, gas and missed-service risk. Record dated role, acceptance or objections, requested revision and attribution consent privately. A changed deal needs both roles to assess the same new revision. Choose duration, amounts, real trade size and cost tolerance from that feedback.
- **Reference and controls.** Recommend the single opening mock source and the limits above for the first comparison. Check feed orientation, precision, stale/future values, exact grid equality, attainable inventory on rerange, delayed execution and recipient-specific failure. Production source, token suitability, actual addresses and deployment choices remain open.
- **Preliminary A2.** On paper compare the same incoming trade intentions, inventory, fee, period and available budget for passive LP with owner exit, the same bounded manager with a time-prorated retainer/escrow, C1, and an observer with programmable settlement. Allow different prices/fills. Ask whether verifiable intervals, fewer reconciliation steps or independent closeout save meaningful buyer or joint effort in flat, interrupted and infeasible-recovery cases. Reduced manager pay alone establishes no joint benefit.
- **Preliminary A3.** Price the proposed workload by payer. Include treasury setup/funding/refund/exit, manager adjustments and claims, trader swap overhead while active/repeated/ended, observer/keeper work, failed transactions, security review and tied-up capital. State assumed counts, gas price, measurement boundaries, exclusions and sensitivity. Seek a buyer-specific break-even condition against the simplest viable alternative. Full lifecycle measurement belongs to M6.
- **Gate decision.** Experimental local implementation may proceed alongside A1 and preliminary A2/A3. Customer acceptance, product-market fit and economic advantage each require their own evidence. If the buyer needs profit or market-relative depth, revisit the proposed service with both roles. Engineering dependencies, final comparison and cost measurement, closeout tests and reproducible demonstration requirements still apply. Authorization covers local mock assets. [Implementation plan](../PLAN.md)
