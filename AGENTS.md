# Unison project instructions

Read PLAN.md, then only the relevant spec, milestone and evidence. Read docs/BUILDING.md only when workflow help is needed. This repository supports a narrow experimental hackathon MVP using local mock assets.

- Scope: one treasury, manager, pair, fixed-fee v4 pool, active position, period and separate compensation budget. No shares, own token, marketplace, AI manager, multichain, renewal or generic executor.
- Enforce PLAN A1–A6/R1–R8. Local experimental implementation may proceed alongside A1 and preliminary A2/A3 validation. Keep these gates pending until supported by customer and economic evidence. Technical completion establishes neither acceptance, product-market fit nor economic advantage. Preserve engineering dependencies, final cost measurement and reproducible demonstration gates.
- Preserve bounded M1 evidence; see docs/M1-STATUS.md. Use the verified experiment import and pinned WSL replay instructions before adapting its code. No full acceptance/funding/refund/closeout pass exists yet.
- Treasury owns principal, idle assets and LP fees. Separate compensation custody; protect unpaid earned reserves and cap claims/refunds by funded rights.
- Termination revokes authority and freezes accrual. Principal exit cannot depend on manager cooperation, compensation/refund transfer success or fresh oracle data; state token/core/chain limits.
- Authenticate PoolManager plus active context; bind pool/owner/ticks/salt; never tx.origin. Checkpoint old state before changes, refresh actual state and clip time; cumulative full-precision base-unit math.
- Pin compatible dependencies; preserve licenses and accurate reuse credits. No unsupported audit, deployment, integration, novelty, performance or prize claims.
- Preserve existing work. No reset/clean, destructive overwrite, force-push, merge, real-fund transactions or deployment without authorization. Outreach requires explicit instructions.
- Establish GitHub remote, branch and publication scope before first push. Check each coherent change, stage intended files, commit and push when authorized; verify success. Aim for 12 meaningful daily commits, never padding/backdating.
- No secrets or private customer responses in Git/frontend/logs. Bind disposable demo controls to endpoint, chain and run identity.
- Start thin frontend reads after M4; connect tested writes after M5; polish after M6. Show contract-backed state and distinguish estimates.
- Record actual results, unresolved decisions, commit/push status and next task in PLAN.md. Do not repeatedly read unrelated history or delegate without authorization.
- Explain plainly and proceed within authorized scope. Limit implementation to the authorized local experiment. Real-fund use and public deployment have no authorization. New local projects default outside OneDrive; do not move existing archives.

## Configured GitHub workflow

Public repository: https://github.com/abdraufdele/Unison. Remote: origin. Work on development, tracking origin/development; main is the default judging branch and includes development through 5c057fb via the authorized regular merge c78173c. The user authorizes routine checked commits and pushes of completed Unison work to this development branch. Do not repeatedly request the established destination or approval for these pushes. Merges, force-pushes, unrelated publication and deployment remain outside this authorization.

- Preserve the individual development commits when integrating into main: use a regular merge commit, never squash or rebase-and-merge. Before any merge, remind the user of this choice and obtain merge authorization; verify the development tip is an ancestor of main afterward. This reminder does not authorize a merge now.
