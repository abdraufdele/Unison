.DEFAULT_GOAL := help
.NOTPARALLEL:
SHELL := /bin/bash
export PYTHONOPTIMIZE :=
NETWORK ?= local
CONFIG ?= config/$(NETWORK).json
MANIFEST ?= .local/ops/$(NETWORK)$(if $(filter dry-run%,$(MAKECMDGOALS)),-simulation).json
ACCOUNT ?=
CONFIRM_CHAIN ?=
ROLE ?= treasury
TARGET ?= vault
FUNCTION ?= currentTerms
ARGS ?= []
INPUTS ?= {}
SEED ?= 0x19112026
OUTPUT ?=
PORT ?= 8545
IPC ?=
SOLC := $(HOME)/.svm/0.8.26/solc-0.8.26
FORGE := forge
FLAGS := --offline --use "$(SOLC)"
PY := python3 -B
FIXTURES := experiments/m6/Comparison.sol test/fixtures/CustodyFixture.sol test/fixtures/MockOpeningReferenceAdapter.sol lib/v4-core/src/PoolManager.sol
export PORT IPC OUTPUT SEED NETWORK CONFIG MANIFEST ACCOUNT CONFIRM_CHAIN ROLE TARGET FUNCTION ARGS INPUTS ACTION RUN_ID TERMS POSITION
NET = $(PY) scripts/ops/network.py --network "$$NETWORK" --config "$$CONFIG" --manifest "$$MANIFEST"
OP = $(PY) scripts/ops/interact.py --network "$$NETWORK" --config "$$CONFIG" --manifest "$$MANIFEST"
ACT = --action "$$ACTION" --role "$$ROLE" --terms "$$TERMS" --run-id "$$RUN_ID" --position "$$POSITION" --inputs "$$INPUTS"

.PHONY: help init all prerequisites deps fmt fmt-check build sizes unit integration fuzz invariant test mutations mutation-clock mutation-reserve mutation-revocation mutation-payment check viewer-install viewer-build viewer-preview artifacts demo statements browser m6 m6-run local-node deploy-local preflight fork dry-run dry-run-local dry-run-sepolia dry-run-mainnet broadcast verify bindings read simulate act-local broadcast-action statement
help: ## Start | List supported targets and inputs (default).
	@awk 'BEGIN {FS=":.*## "} /^[a-z][a-z0-9-]*:.*## / {split($$2,p," \\| "); printf "%-14s %-20s %s\n",p[1],$$1,p[2]}' $(firstword $(MAKEFILE_LIST))
init: ## Build | Restore the four exact root dependency submodules.
	git submodule update --init -- lib/v4-core lib/solmate lib/forge-std lib/openzeppelin-contracts
all: check ## Checks | Run all local checks sequentially.
prerequisites: ## Build | Verify native tools, exact git pins and M1 hashes.
	$(PY) scripts/verify.py pins
deps: prerequisites ## Build | Verify installed prerequisites and locked viewer packages.
	$(PY) scripts/ops/checkRouting.py
	npm --prefix viewer ls --all > /dev/null
fmt: ## Build | Format project-owned active Solidity files.
	$(FORGE) fmt src test script
fmt-check: ## Build | Check formatting without editing.
	$(FORGE) fmt --check src test script
build: ## Build | Compile the root suites, Foundry scripts and viewer/deployment fixtures.
	$(FORGE) build $(FLAGS)
	$(FORGE) build $(FLAGS) $(FIXTURES)
sizes: build ## Build | Check product size limits and the complete selector inventory.
	$(PY) scripts/verify.py artifacts
unit: ## Tests | Run isolated arithmetic and consent checks.
integration: ## Tests | Run cross-contract and real-core scenarios.
fuzz: ## Tests | Run the parameterized suites with SEED.
invariant: ## Tests | Run the stateful handler campaign with SEED.
unit integration fuzz invariant:
	$(FORGE) test $(FLAGS) --match-path 'test/$@/*.t.sol' --fuzz-seed "$$SEED" -vv
test: ## Tests | Run the complete discovered suite with SEED.
	$(FORGE) test $(FLAGS) --fuzz-seed "$$SEED" -vv
mutation-clock: ## Mutations | Check old-state checkpoint detection.
	bash scripts/check_service_clock_mutation.sh
mutation-reserve: ## Mutations | Check earned reserve protection.
	bash scripts/check_reserve_mutation.sh
mutation-revocation: ## Mutations | Check post-expiry management rejection.
	bash scripts/check_closeout_mutation.sh revocation
mutation-payment: ## Mutations | Check independent principal receipt.
	bash scripts/check_closeout_mutation.sh payment
mutations: mutation-clock mutation-reserve mutation-revocation mutation-payment ## Mutations | Run the four isolated compiled regressions.
check: deps fmt-check sizes test mutations artifacts viewer-build m6 browser check-actions ## Checks | Run full local verification, including owned browser fixtures.
viewer-install: ## Viewer | Install locked npm dependencies.
	npm --prefix viewer ci --no-audit --no-fund
viewer-build: ## Viewer | Type-check and build the viewer.
	npm --prefix viewer run build
viewer-preview: ## Viewer | Serve the built viewer on loopback until interrupted.
	npm --prefix viewer run preview
artifacts: build ## Viewer | Validate generated read ABI and source/build identity.
	$(PY) scripts/viewer/artifacts.py --check
demo: ## Viewer | Launch the existing identity-bound interactive local demo.
	$(PY) -u scripts/viewer/demo.py
statements: ## Viewer | Run isolated browser statement scenarios (requires preview and CHROMIUM_PATH).
	$(PY) -u scripts/viewer/check_statement.py
browser: ## Viewer | Start an owned preview, run both browser suites and stop its services.
	$(PY) -u scripts/viewer/replay.py
m6: ## Evidence | Reconcile historical published comparison tables.
	$(PY) experiments/m6/check.py
m6-run: ## Evidence | Measure current code into an empty OUTPUT directory and reconcile.
	@test -n "$$OUTPUT"
	$(PY) -u experiments/m6/run.py "$$OUTPUT"
	$(PY) experiments/m6/check.py "$$OUTPUT"
local-node: ## Deployment | Start loopback Anvil with PORT (default 8545) and optional IPC path.
	anvil --host 127.0.0.1 --port "$$PORT" --chain-id 31337 --hardfork cancun --mnemonic-random 12 --quiet $${IPC:+--ipc "$$IPC"}
deploy-local: ## Deployment | Create a draft on local-node, writing a new MANIFEST.
	$(NET) local
preflight: ## Deployment | Check NETWORK/CONFIG endpoint, header and deployed core.
	$(NET) preflight
fork: ## Deployment | Exercise the deployed core on a pinned owned fork (NETWORK=sepolia or mainnet).
	$(NET) fork
dry-run: ## Deployment | Simulate NETWORK/CONFIG into a fresh MANIFEST; local uses owned IPC.
	$(NET) dry-run --account "$$ACCOUNT"
dry-run-local: ## Deployment | Simulate disposable C1 setup on owned IPC.
dry-run-sepolia: ## Deployment | Simulate C1 mock deployment on pinned Sepolia.
dry-run-mainnet: ## Deployment | Evaluate mainnet C1 preparation prerequisites.
dry-run-local: override NETWORK = local
dry-run-sepolia: override NETWORK = sepolia
dry-run-mainnet: override NETWORK = mainnet
dry-run-local dry-run-sepolia dry-run-mainnet:
	$(NET) dry-run --account "$$ACCOUNT"
broadcast: ## Future submission | Explicit Sepolia deployment with CONFIG, new MANIFEST, ACCOUNT and CONFIRM_CHAIN=1301.
	$(NET) broadcast --account "$$ACCOUNT" --confirm-chain "$$CONFIRM_CHAIN"
bindings: ## Deployment | Verify live manifest identity, bytecode, recipients and CREATE2.
	$(NET) bindings
verify: ## Future submission | Verify deployed Sepolia contracts on the explorer using MANIFEST.
	$(NET) verify
read: ## Interaction | Read a compiled view with TARGET, FUNCTION and JSON ARGS.
	$(OP) read --target "$$TARGET" --function "$$FUNCTION" --args "$$ARGS"
simulate: ## Interaction | eth_call a named ACTION with ROLE, RUN_ID, TERMS, POSITION and JSON INPUTS.
	$(OP) simulate $(ACT)
act-local: ## Interaction | Send a supported action on the validated local run.
	$(OP) send-local $(ACT)
broadcast-action: ## Future submission | Explicit Sepolia lifecycle transaction, ACCOUNT and matching CONFIRM_CHAIN.
	$(OP) broadcast $(ACT) --account "$$ACCOUNT" --confirm-chain "$$CONFIRM_CHAIN"
statement: ## Interaction | Export block-pinned JSON for a funded MANIFEST to stdout (use make -s).
	$(OP) statement
.PHONY: rehearse check-actions
rehearse: ## Interaction | Run the Foundry purchase and closeout simulation against a fresh verified draft.
	$(NET) rehearse
check-actions: ## Interaction | Exercise reads, simulation, local sends and statement export on an owned chain.
	$(PY) -u scripts/ops/checkLocal.py

# The transport wrapper selects a single typed .s.sol function and reconciles Forge's journal.
FORGE_SUITE = $(PY) -u scripts/ops/forgeSuite.py
export ACTOR TERMS EXPECTED_STATE POSITION DEADLINE BOUNDS_CONFIG REFERENCE_CONFIG UNISON_TREASURY UNISON_MANAGER
.PHONY: foundry-build foundry-config foundry-deploy-local foundry-rehearse foundry-fork foundry-verify foundry-action foundry-action-local foundry-action-broadcast
.PHONY: foundry-preflight-sepolia foundry-preflight-mainnet foundry-simulate-local foundry-simulate-sepolia foundry-simulate-mainnet foundry-broadcast-sepolia foundry-broadcast-mainnet
foundry-build: ## Foundry | Compile the deployment, fixture and typed interaction entry points and their runtime artifacts.
	$(FORGE) build $(FLAGS) script/deploy/*.s.sol script/interact/*.s.sol script/fixtures/*.sol $(FIXTURES)
foundry-config: ## Foundry | Run the selected network entry point's read-only Solidity preflight.
	$(FORGE_SUITE) preflight
foundry-deploy-local: override NETWORK = local
foundry-deploy-local: ## Foundry | Mine DeployLocal on loopback Anvil with a fresh MANIFEST.
	$(FORGE_SUITE) deploy
foundry-preflight-sepolia foundry-simulate-sepolia foundry-broadcast-sepolia: override NETWORK = sepolia
foundry-preflight-mainnet foundry-simulate-mainnet foundry-broadcast-mainnet: override NETWORK = mainnet
foundry-simulate-local: override NETWORK = local
foundry-preflight-sepolia foundry-preflight-mainnet: foundry-config
foundry-simulate-local foundry-simulate-sepolia foundry-simulate-mainnet:
	$(FORGE_SUITE) simulate
foundry-broadcast-sepolia foundry-broadcast-mainnet:
	@test -n "$$ACCOUNT" && { [[ "$$NETWORK:$$CONFIRM_CHAIN" == sepolia:1301 ]] || [[ "$$NETWORK:$$CONFIRM_CHAIN" == mainnet:130 ]]; }
	$(FORGE_SUITE) deploy
foundry-verify: ## Foundry | Verify chain receipts and execute VerifyDeployment.s.sol on a mined record.
	$(FORGE_SUITE) verify
foundry-action: ## Foundry | Simulate ACTION with ACTOR, RUN_ID, TERMS, POSITION, EXPECTED_STATE, DEADLINE and JSON ARGS.
	$(FORGE_SUITE) action
foundry-action-local: override NETWORK = local
foundry-action-local: ## Foundry | Mine one typed action on the manifest's local Anvil.
	$(FORGE_SUITE) send
foundry-action-broadcast: ## Future submission | Send exactly one typed public operation using ACCOUNT and matching CONFIRM_CHAIN.
	@test -n "$$ACCOUNT" && { [[ "$$NETWORK:$$CONFIRM_CHAIN" == sepolia:1301 ]] || [[ "$$NETWORK:$$CONFIRM_CHAIN" == mainnet:130 ]]; }
	$(FORGE_SUITE) send
foundry-rehearse: foundry-build ## Foundry | Run both complete mined lifecycle scenarios on owned local IPC chains.
	$(PY) -u scripts/ops/forgeLifecycle.py local
foundry-fork: foundry-build ## Foundry | Run script-driven lifecycle on the selected pinned public core through owned IPC.
	@test "$$NETWORK" = mainnet || test "$$NETWORK" = sepolia
	$(PY) -u scripts/ops/forgeLifecycle.py "$$NETWORK"
