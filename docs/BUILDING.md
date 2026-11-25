# Build workflow

Read [PLAN.md](../PLAN.md), then only the relevant spec, milestone and evidence. [AGENTS.md](../AGENTS.md) contains persistent rules. The [M1 import record](../experiments/m1/README.md) identifies the preserved evidence and source.

## Starting point

M1 compatibility/accounting passed in a bounded experiment. The separate root suite covers C1 consent, funding, cancellation, activation, bounded management, service accounting, compensation and independent closeout. Use the [root setup commands](../README.md#setup) for those tests. Local engineering checks have passed; customer fit, buyer-specific economic justification and independent A6 reproduction remain open.

Use [candidate C1](SERVICE-SPEC.md) for the narrow local hackathon implementation. A1 and preliminary A2/A3 continue in parallel. Engineering checks, final cost measurement and reproducible demonstration requirements still apply.

## Initial prompt

```text
Read AGENTS.md and PLAN.md. Inspect the current files and Git state.
Complete the next authorized, dependency-ready task only.
Use the imported M1 source and pinned WSL replay as the engineering baseline.
Keep customer acceptance and preliminary A2/A3 pending until evidence supports them.
Distinguish proposals, implemented behavior and executed evidence.
Run appropriate checks and record results, defects and next action.
Use local mock assets. Outreach, real funds and public deployment need separate authorization.
```

## Continue

```text
Continue the next authorized task in PLAN.md. Read only relevant files.
Implement one coherent change, check it, inspect the diff and update
the evidence/status. Commit intended files and push to the agreed
GitHub branch when authorized; verify push success.
Preserve existing work. Do not manufacture work to meet commit targets.
```

## Repository discipline

- Work in the current project root; preserve the separate research archive and existing M1 experiment. No machine-specific absolute paths are required.
- Use AGENTS.md (plural), not AGENT.md. Keep it compact; detail belongs in the plan/spec/tests.
- Establish GitHub destination, branch and publication scope before first push. The user wants incremental commits/pushes; do not publish private feedback or unrelated research.
- Aim for 12 meaningful commits per working day across seven days, not time-triggered snapshots. No padding, empty commits, backdating, force-push or rewriting published history.
- Each task: inspect diff, run appropriate checks, stage explicit files, commit, authorized push, verify. Keep coherent code and tests together; report actual counts if blocked.
- Keep original third-party licenses and accurate reused/new-work credits. A neutral folder name does not change project provenance.
- No copied account credentials, browser state, package caches or machine-specific tool configuration.

## Frontend and optional integrations

Sketch in M0; define interfaces during M3; start real read-only UI after M4; connect tested writes after M5; polish after M6. Show authoritative amounts and transaction state. No fake balances or frontend-only settlement.

Safe ownership is the first optional integration after core closeout. A suitable opening-reference adapter is conditional on actual assets/network. Tenderly is optional inspection tooling; do not assume its API/virtual environment is free. Professional manager adapters need a separate compatibility proof and buyer need.

## Definition of done

All shipped promises map to source, tests and a reproducible action. Full closeout, customer acceptance and final economics remain separate gates. A short prompt saves repeated input, not a guaranteed percentage of total tokens. Historical evidence dates and negative results stay intact.
