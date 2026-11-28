# C1 developer commands

For the explicit Solidity network entry points, encrypted signer commands, typed lifecycle operations and mined receipt checks, use the [Foundry runbook](FOUNDRY-OPERATIONS.md).

Use the pinned Linux tools and dependency checkout in the [setup instructions](../README.md#setup). Run commands from the repository root. `make help` groups targets by purpose. Target names use lowercase words separated by hyphens. `make` prints help. `make check` runs the full local suite sequentially, including four isolated mutation builds and fresh browser fixtures. Install the pinned viewer packages and Playwright browser first.

```sh
make init
make prerequisites
make viewer-install
export CHROMIUM_PATH="$PWD/.local/verification/browsers/chromium_headless_shell-1193/chrome-linux/headless_shell"
make deps fmt-check build sizes
make unit integration fuzz invariant SEED=0x19112026
make artifacts viewer-build browser
make m6
make m6-run OUTPUT=.local/ops/current-comparison
```

`make fmt` formats project Solidity. `make test` runs all discovered categories in one invocation. `make mutations` checks the four deliberate defects in fresh ignored copies. `make demo` and `make viewer-preview` launch the original interactive browser journey in separate terminals. `make statements` exercises exports against an existing preview. For a different checkout or browser installation, set CHROMIUM_PATH to its actual executable. [Viewer runbook](LOCAL-VIEWER.md)

## Networks and fork pins

| NETWORK | Chain | Official PoolManager | Simulation block |
|---|---:|---|---:|
| local | 31337 | New pinned core on disposable Anvil | Local head |
| sepolia | 1301 | 0x00b036b58a818b1bc34d502d3fe730db729e62ac | 68880930 |
| mainnet | 130 | 0x1f98400000000000000000000000000000000004 | 64985000 |

The corresponding configs record RPC, block hash and core runtime keccak. Network configuration and PoolManager addresses were checked against the official references. Alternate providers must serve the configured history. Put credential-bearing URLs in a private environment variable, `UNISON_RPC_URL`, without shell tracing. The manifest stores an endpoint digest. Both deployment and subsequent reads require the same provider identity. [Unichain network information](https://developers.uniswap.org/docs/unichain/technical-information/network-information) · [Uniswap v4 deployments](https://developers.uniswap.org/docs/protocols/v4/deployments)

```sh
make preflight NETWORK=sepolia
make fork NETWORK=sepolia
make fork NETWORK=mainnet
make dry-run NETWORK=sepolia MANIFEST=.local/ops/sepolia-simulation.json
make dry-run NETWORK=local MANIFEST=.local/ops/local-simulation.json
make dry-run NETWORK=mainnet MANIFEST=.local/ops/mainnet-simulation.json
```

On either Unichain config, preflight checks the chain, header, actual deployed code and extsload response. Local preflight checks the chain ID and expected Anvil client. The fork rehearsal uses a separate owned Anvil IPC socket. On that fork it funds two mock assets, checks exact seed costs, activates against the configured core, sends a swap to the upper tick and recovers the position after stopping. Archive availability and a completed behavior run determine the evidence for each pin. Mainnet deployment preparation exits before creating any transaction. C1 lacks a reviewed pair of ordered, ordinary exact-transfer six-decimal tokens and a suitable independent eight-decimal opening source with a justified 60-second freshness interval. A mock-asset fork rehearsal cannot satisfy these prerequisites.

## Deployment and verification

Start `make local-node` in its own terminal. Then run the following commands. Select a new manifest path for each new agreement. The driver creates the journal exclusively and records each intent and receipt. An interrupted deployment leaves a partial journal. Inspect its hash, nonce, receipts and deployed code before any manual recovery. The driver has no automatic resume or redeploy.

```sh
export NETWORK=local MANIFEST=.local/ops/agreement.json
make preflight
make deploy-local
make bindings
make read TARGET=vault FUNCTION=currentTerms
```

Local and Sepolia fixtures create explicitly unrestricted mock tokens and an unrestricted mock opening adapter. The vault is created directly by the named treasury. The Foundry CreateVault rehearsal constructs the vault with the selected compiled artifact and validates treasury ownership. Compilation targets Cancun. The pinned Unichain simulations use the Karst OP Stack runtime. The driver separately checks the treasury CREATE receipt, constructor arguments, runtime and ownership. The driver obtains the actual vault address from the CREATE receipt. The vault starts with two empty draft addresses and no consent. A dedicated factory installs the hook bound to the actual vault and ordered currencies. Salt search uses the factory address, 32-byte salt and full constructor init-code hash to obtain flags 0x0840. The escrow binds the same vault, token B and both fixed recipients. Revision two installs these actual addresses before either party accepts. The quote helper is the first child created by the new vault. Runtime comparison masks compiler-declared immutable offsets, then checks domain and party getters, complete pool ID, both recipients, constructor inputs and actual runtime hashes. Funding verifies exact token balance deltas.

The manifest includes network, endpoint digest, Git revision, compiler and Foundry identities, per-contract constructor bytes and creation hashes, hook mining data, deployed code sizes and hashes, and the mined receipts in that environment. A simulation manifest belongs to its temporary node. Verification of a live deployment requires a matching anchor and chain. The initial terms hash identifies the deployed revision. The complete current terms hash must be reviewed again after an edit.

For a **future separately authorized** Sepolia submission, copy config/sepolia.json outside Git, add distinct public treasury and manager addresses using fields `treasury` and `manager`, and import the treasury wallet into Foundry's encrypted keystore outside this repository. The network uses test mocks. The following commands describe the entry points for that future operation. Explorer verification requires the provider's private Etherscan credential in its supported environment variable.

```sh
make broadcast NETWORK=sepolia CONFIG=.local/ops/reviewed-sepolia.json MANIFEST=.local/ops/sepolia-live.json ACCOUNT=treasury CONFIRM_CHAIN=1301
make bindings NETWORK=sepolia CONFIG=.local/ops/reviewed-sepolia.json MANIFEST=.local/ops/sepolia-live.json
make verify NETWORK=sepolia CONFIG=.local/ops/reviewed-sepolia.json MANIFEST=.local/ops/sepolia-live.json
```

## Named lifecycle operations

`make read` accepts only compiled view/pure entries on vault, hook, escrow, quote, adapter and the mock pair. Supply positional JSON ARGS for parameterized reads. The [selector table](SELECTORS.md) identifies getters, user actions and authenticated internal entry points. A write first checks the endpoint, chain, manifest marker, code, recipient bindings and current terms hash, then simulates the typed action against its actor and current state. The final chain execution enforces the contract's caller, deadline, balance and position checks. Unparameterized ABI calls retain their onchain semantics if another transaction changes state between preview and inclusion.

```sh
export RUN_ID=$(python3 -c 'import json,os; print(json.load(open(os.environ["MANIFEST"]))["runId"])')
export TERMS=$(make -s read TARGET=vault FUNCTION=termsHash | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')
make simulate ACTION=accept ROLE=treasury
make act-local ACTION=accept ROLE=treasury
make act-local ACTION=accept ROLE=manager
make act-local ACTION=approveA
make act-local ACTION=approveB
make act-local ACTION=fund
make act-local ACTION=publishOpening
make read FUNCTION=previewOpeningReference
make read FUNCTION=preflightActivation ARGS='["'"$TERMS"'"]'
make act-local ACTION=activate
make read TARGET=hook FUNCTION=qualification
make read TARGET=escrow FUNCTION=reserved
```

`approveA` authorizes exactly the C1 inventory and `approveB` authorizes inventory plus the separate budget. Before funding, `revise` accepts JSON INPUTS with a verified mock adapter and its source. Both parties review the new hash and accept again. `cancel` and `withdrawIdle` recover unactivated principal, and `refund` pulls any funded terminal remainder. Anyone can trigger the contract's fixed-recipient payments. The CLI supports both named parties for those calls.

After the 30-second adjustment cooldown, obtain the displayed position ID. Adjustments use this exact ID, a current block timestamp, a caller-selected TTL of at most 30 seconds and explicit limits in token base units. The following example is a simulation at parity. Refresh the ID, terms and limits for each actual action.

```sh
export POSITION=$(make -s read FUNCTION=positionId | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')
make simulate ACTION=rerange ROLE=manager INPUTS='{"ttl":20,"tickLower":-1,"tickUpper":1,"lower":-180,"upper":180,"liquidity":100000000000,"maxInput0":900000000,"maxInput1":900000000,"minOutput0":598000000,"minOutput1":598000000}'
```

`add` uses the same fields and `remove` omits lower and upper. `checkpoint` persists service through the current chain time. `claim` pays earned units to the manager. The treasury can terminate early or either role can finalize effective expiry. Then the treasury can exit liquidity and withdraw idle assets, and either role can pull the refund and unpaid claim independently. Mock route failures and accelerated time in the browser remain restricted to its identity-bound disposable launcher.

```sh
make act-local ACTION=terminate
make act-local ACTION=exitLiquidity
make act-local ACTION=withdrawIdle
make act-local ACTION=refund
make act-local ACTION=claim ROLE=manager
make -s statement > .local/ops/statement.json
```

The statement collector checks one funded agreement over its bounded local history (fewer than 128 blocks from creation, at most eight transactions per block and 1,024 product logs). It verifies receipt ancestry, events, token movements and projected rights. The CLI journal covers confirmed product events. The browser additionally retains failed action receipts from its fixed journey. Historical nodes or busy public blocks can exceed the exporter's limits.

`broadcast-action` is a separate future Sepolia entry point. It requires ACCOUNT, CONFIRM_CHAIN=1301, the live MANIFEST, RUN_ID, current TERMS and the same named action inputs. Authenticated hook callbacks, escrow credit, vault-only clock installation and the core unlock callback are reached through legitimate protocol operations.

On a new local draft `make rehearse` runs RehearseAgreement.s.sol through Forge without a broadcast flag. The Foundry simulation plans both actors' acceptances, fixed approvals, funding, opening, activation, termination, independent principal exit, claim and refund. The wrapper verifies the live manifest before running it. `make check-actions` exercises the documented operator entry points on a fresh loopback chain, checks rejected stale hashes and unauthorized roles, branches through funded cancellation and expiry on owned snapshots, then reconciles a terminal export.

For a fresh Python environment use `python3 -m venv .local/ops/venv`, activate it and run `python -m pip install -r requirements-dev.txt`. These pins record the direct dependencies used in the original fixture environment. The fork reader, deployment CLI and viewer use those same packages.

On the checked Linux install, npm 11.21.3 warned that esbuild@0.25.12's postinstall was outside its allowScripts list. npm's install log recorded that script completing with status 0. TypeScript checking and the Vite production build succeeded with the installed lockfile. The checked setup requires no additional script permission.

## Command verification

The default target prints help. The two aggregate aliases were executed together with GNU Make dependency deduplication. The category targets were also executed individually in that sequential invocation. The following rows distinguish completed commands, tested rejections and unavailable external operations.

| Result | Targets and evidence |
|---|---|
| Passed | Default, help, prerequisites, deps, fmt, fmt-check, build and sizes. Formatting produced no source changes. Sizes checked 100 concrete product selectors and the three interfaces. |
| Passed | unit, integration, fuzz, invariant and test. The four mutation targets and mutations required the baseline, successful mutant compile and exact failing assertion. |
| Passed | viewer-install, viewer-build, artifacts, viewer-preview, statements, demo and browser. The browser harness used the actual preview and demo Make targets, validated the run identity and stopped its own children. |
| Passed | m6 reconciled the original CSVs. m6-run created and reconciled a new measurement in an empty directory. |
| Passed on disposable chains | local-node, deploy-local, dry-run with NETWORK=local, bindings, rehearse, read, simulate, act-local, statement and check-actions. The local check exercised both funded cancellation and expiry, all three manager operations, early termination and payments. |
| Passed on pinned network inputs | preflight, fork, dry-run-local and dry-run-sepolia. Each fork ran the real deployed core on owned IPC with fixture assets. |
| Expected rejection | dry-run-mainnet rejected its missing mainnet prerequisites. Both dedicated broadcast targets rejected missing chain confirmation and account before transaction submission. |
| External success path not run | Public broadcast, public lifecycle submission and explorer verification require an authorized deployment and signer or explorer credentials. The local verify rejection was exercised. |
| Passed | check and all. The aggregate local verification exited 0. |

The [development evidence](DEVELOPMENT-EVIDENCE.md) gives campaign counts, contract sizes and fresh gas figures. The [network checks](NETWORK-CHECKS.md) give pins and simulated deployment identities.

The final operator check uses both named fields from the hook's qualification read. Its first expanded assertion used a numeric index and failed before closeout. The corrected check exited 0 on the freshly built artifacts. At block 33 the 100 B budget reconciled to 51 B claimed and 49 B refunded. Treasury principal recovery, zero remaining position liquidity and zero outstanding escrow rights reconciled. The fresh build procedure and original failure are recorded in [development evidence](DEVELOPMENT-EVIDENCE.md#isolated-build-and-final-operator-result).


## Dependency layout

Active Solidity dependencies live in root `lib/` as exact Git submodules. Run `make init` on a fresh checkout; root `remappings.txt` is the only active remapping list. See [pins and roles](DEPENDENCIES.md). The isolated M1 replay retains its historical vendor configuration. Library upgrades and copying a competitor implementation are outside this organization change.
