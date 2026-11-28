# Foundry deployment and operations

The network entry points create one C1 vault, its separate compensation escrow and bound service hook. The treasury sends the vault CREATE directly. Revision one contains empty hook and escrow placeholders. The script mines the salt from the current ServiceHook creation bytecode, deploys through the dedicated HookInstaller, revises the draft and initializes its fixed-fee pool. Revision two has zero consent, funding and position liquidity. The vault's immutable OpeningQuote is its first constructor child. Only the local entry point creates a PoolManager.

## Build and rehearse

Use the pinned Linux setup and installed Python requirements from the repository root. Each deployment and interaction is constructed by its Solidity script. The Python wrapper handles signer transport, journaling and independent receipt reconciliation.

```sh
make init prerequisites foundry-build
make foundry-rehearse
make foundry-fork NETWORK=sepolia
make foundry-fork NETWORK=mainnet
```

The rehearsal starts disposable Anvil processes with random accounts. Each selected Solidity operation runs in a separate Forge invocation as one actor. The fork runner restricts the upstream relay to reads and sends transactions only to its own Anvil IPC socket. The mainnet fork uses separately created stand-ins to exercise the external-dependency configuration. The local fault case deliberately selects the separate adversarial CustodyToken fixture. Regular local and Sepolia demo deployments use fixed-supply DemoToken and a publisher-bound DemoReference. The runner prints the ignored evidence directory with manifests, transaction journals, actual balances and results.

## Deploy a local draft

Start `make local-node` in another terminal. The local RPC must be loopback Anvil. Select the first two **public addresses** returned by the node. The following commands assume Bash, the pinned tools and a new manifest filename.

```sh
export NETWORK=local CONFIG=config/local.json ETH_RPC_URL=http://127.0.0.1:8545
mapfile -t actors < <(cast rpc eth_accounts | python3 -c 'import json,sys; print(*json.load(sys.stdin), sep="\n")')
export UNISON_TREASURY="${actors[0]}" UNISON_MANAGER="${actors[1]}"
export RUN_ID="0x$(openssl rand -hex 32)" MANIFEST=".local/ops/draft-${RUN_ID}.json"
make foundry-config
make foundry-simulate-local MANIFEST=".local/ops/preview-${RUN_ID}.json"
make foundry-deploy-local
make foundry-verify
make foundry-action ACTION=read
```

## Public configuration and signer selection

Use network config under `config/` or an ignored reviewed copy under `.local/ops/`. Set `UNISON_RPC_URL` privately for a credential-bearing provider. Leave shell tracing off. Forge receives the `unison_script` alias. The wrapper verifies the configured chain, pinned block hash, deployed PoolManager code identity and external storage read. The Solidity entry point independently pins the official public core and expected runtime. The fork pins and runtime settings are in [the network evidence](NETWORK-CHECKS.md). The canonical contracts and chain IDs were checked against the [Uniswap v4 deployments](https://developers.uniswap.org/docs/protocols/v4/deployments) and [Unichain network information](https://developers.uniswap.org/docs/unichain/technical-information/network-information).

Supply distinct `UNISON_TREASURY` and `UNISON_MANAGER` public addresses and a unique `RUN_ID`. Production JSON must also specify matching `treasury` and `manager`. For each future public submission, set `ACCOUNT` to one Foundry encrypted keystore name. The wrapper derives its public address and compares it to the selected signer before submission. Use an interactive terminal for wallet unlocking. Simulation uses the public sender address alone. Private keys and passwords do not belong in arguments, configs, journals or Git.

The checked-in mainnet config lacks production asset and reference inputs. For a reviewed pair, add the following fields to a private copy of config/mainnet.json.

| Field | Required evidence or value |
|---|---|
| `fixtureAssets` | false for external dependencies |
| `treasury`, `manager` | Reviewed fixed recipient and signer addresses |
| `token0`, `token1` | Ascending ERC-20 addresses, both six decimals, exact debit/receipt, non-rebasing, compatible approval and transfer behavior |
| `adapter`, `source` | Reviewed contracts. Adapter returns the C1 observation for token1 units per token0, with a positive eight-decimal answer |
| `token0Hash`, `token1Hash`, `adapterHash`, `sourceHash` | Expected keccak256 values of deployed runtime code, independently obtained during dependency review |
| `initialSqrtPriceX96` | Explicit reviewed launch price as an integer or decimal string. Its tick must be inside the outward-rounded reference band |

Review token behavior, upgrade controls and proxy implementation identities where applicable. Runtime hashes authenticate the observed code at each supplied address. A proxy runtime hash alone cannot establish its current implementation, future transferability or the economic suitability of a feed. The scripts check order, code, observable scales, quote direction/source, completeness, age at most 60 chain seconds, representability, seed price, liquidity and gross input feasibility. Funding and activation repeat their onchain checks. The deployment script initializes the new pool at the supplied price. Include that transaction in the price review.

For the following current-head commands, export the intended public addresses, run ID, network, config and fresh manifest. The pinned OP Stack Forge runtime can check the sender's native gas balance even while running a read-only script. A direct mainnet-head attempt with an unfunded disposable address stopped at that check. The owned-fork rehearsals use locally funded actors. Use the corresponding network's reviewed sender for a live-head simulation.

```sh
make foundry-preflight-sepolia CONFIG=config/sepolia.json
make foundry-simulate-sepolia CONFIG=config/sepolia.json MANIFEST=.local/ops/sep-preview.json
make foundry-preflight-mainnet CONFIG=.local/ops/reviewed-mainnet.json
make foundry-simulate-mainnet CONFIG=.local/ops/reviewed-mainnet.json MANIFEST=.local/ops/main-preview.json
```

Future public commands require separate authorization, the matching funded account, reviewed configuration, fresh manifest and explicit chain confirmation. They were not executed.

```sh
make foundry-broadcast-sepolia CONFIG=.local/ops/reviewed-sepolia.json MANIFEST=.local/ops/sep-live.json ACCOUNT="$TREASURY_ACCOUNT" CONFIRM_CHAIN=1301
make foundry-broadcast-mainnet CONFIG=.local/ops/reviewed-mainnet.json MANIFEST=.local/ops/main-live.json ACCOUNT="$TREASURY_ACCOUNT" CONFIRM_CHAIN=130
```

## Typed operations

Each invocation checks the mined manifest, endpoint, chain, agreement, current terms and position. For writes, supply `ACTOR`, `RUN_ID`, `TERMS`, `POSITION`, `EXPECTED_STATE` and an absolute `DEADLINE` based on chain time. Accepts and funding commit to the hash onchain. Manager operations additionally commit to position and execution limits onchain. For methods whose ABI has no hash, state or deadline parameter, those checks take place during script simulation. Inclusion can follow another transaction or a state change. Re-read after each receipt and revision.

A local treasury acceptance from a fresh draft can be performed as follows. Review the `read` output and manifest before selecting the parameters.

```sh
export ACTOR="$UNISON_TREASURY" EXPECTED_STATE=0
export TERMS="$(python3 -c 'import json,os;print(json.load(open(os.environ["MANIFEST"]))["termsHash"])')"
export POSITION="0x$(printf '%064d' 0)"
export DEADLINE="$(( $(cast block latest --field timestamp) + 30 ))"
make foundry-action ACTION=accept
make foundry-action-local ACTION=accept
```

Repeat acceptance independently as the manager with a fresh deadline. Once both have accepted, set `ACTOR` to treasury and `EXPECTED_STATE=1`. Invoke `approveFunding` twice with `ARGS='["false"]'` and `ARGS='["true"]'`, then `fund`. After funding use `EXPECTED_STATE=2`. For a demo reference call `refresh` before `preview`, `preflightActivation` and `activate`. Use `make foundry-action` to simulate any operation, `make foundry-action-local` for a single local transaction, and `make foundry-verify` for mined construction and current bindings.

| Solidity file | Individually selectable operations and inputs |
|---|---|
| script/deploy/DeployLocal.s.sol | `preflight()`, `run()` on 31337, local core and C1 deployment |
| script/deploy/DeployUnichainSepolia.s.sol | Same signatures on 1301, canonical core and clearly labeled demo assets or configured external assets |
| script/deploy/DeployUnichainMainnet.s.sol | Same signatures on 130, external pair/reference required |
| script/deploy/VerifyDeployment.s.sol | `run()` reads verified live bindings, terms hash and position |
| script/interact/ReadAgreement.s.sol | `read` returns terms, state, position, qualification and payment. `preview`, `preflightActivation` and `verifySettlement` inspect opening or final recovery. Final return includes any unsolicited escrow surplus |
| script/interact/AgreementActions.s.sol | `revise`, `accept`, `approveFunding(bool)`, `fund`, `activate`, `cancel`. C1 revision supports new reference bindings under fixed economic parameters. Supply `REFERENCE_CONFIG` with `adapter`, `source` and their runtime hashes |
| script/interact/ManagePosition.s.sol | `add(lower,upper,liquidity)`, `remove(liquidity)`, `rerange(lower,upper,liquidity)`. Supply arguments as a JSON array and `BOUNDS_CONFIG` |
| script/interact/SettlementActions.s.sol | `checkpoint`, `claim`, `terminate`, `finalizeExpiry`, `exitLiquidity`, `withdrawIdle`, `refund`. Treasury performs early termination and principal recovery. Anyone allowed by the script may trigger settlement to its fixed recipients |
| script/interact/FixtureOpening.s.sol | `refresh` updates the publisher's parity timestamp only on an explicitly recorded local/Sepolia fixture |

State values are Draft 0, Accepted 1, Funded 2, Cancelled 3, Active 4, Terminated 5 and Expired 6. An active manager order requires the current position ID and an explicit bounds file with `validFrom`, `tickLower`, `tickUpper`, `maxInput0`, `maxInput1`, `minOutput0`, `minOutput1`. The tick bounds constrain the execution tick. The ticks in `ARGS` select the LP range. Quote and review all amounts in token base units. The interval from `validFrom` to `DEADLINE` may span at most 30 seconds. C1 also enforces a 30-second adjustment cooldown.

```sh
make foundry-action ACTION=add ARGS='[-120,120,10000000000]' BOUNDS_CONFIG=.local/ops/order.json
make foundry-action ACTION=remove ARGS='[10000000000]' BOUNDS_CONFIG=.local/ops/order.json
make foundry-action ACTION=rerange ARGS='[-180,120,100000000000]' BOUNDS_CONFIG=.local/ops/order.json
# Future, independently authorized public interaction with the actor's encrypted account
make foundry-action-broadcast NETWORK=sepolia ACTION=accept ACCOUNT="$MANAGER_ACCOUNT" CONFIRM_CHAIN=1301
```

The compiled product selectors, including getters, are inventoried by contract. The same-name typed operations above implement the lifecycle routes and the existing ABI-filtered `make read` covers individual getters, including OpeningQuote, settlementContext and the IC1Token reads. The deployer uses factory installation and PoolManager initialization. PoolManager callbacks, vault-only hook calls, escrow credit and token movement inside custody are protocol-only. DemoToken metadata, balances and allowances are ERC-20 reads. Its ordinary transfers can supply a disposable trader. DemoReference observation and publisher are reads and refresh is fixture-only. [Selector-by-selector map](SELECTORS.md)

## Records, partial sends and verification

`MANIFEST` uses the existing `unison.deployment.v1` schema. The Solidity recipe records simulated constructor inputs and CREATE2 identity. The wrapper adds the git revision/dirty flag, dependency pins, compiler, Forge version, source and runtime fingerprints, recipients, reference source, network and mode. Check `status` first. `simulated` contains predicted addresses and terms, zero receipts and no mined anchor. A completed broadcast reconciles Forge's transaction hashes and payloads with RPC receipts. It reads the anchor, runtime hashes and final terms from the mined chain. The vault creation timestamp can change the terms hash. A fork-rehearsal record belongs to its disposable endpoint.

The wrapper reserves a new filename exclusively and keeps its sibling .forge/ directory for the recipe, Forge output and per-action journals. An interrupted process can leave `building` or `partial`. Preserve both files and the ignored Forge cache. Inspect the sender's pending and mined nonces, all journaled hashes, block inclusion, receipt status, CREATE addresses, factory call, hook flags and installed revision. Compare the recorded calldata with compiled constructors before deciding about any recovery. A simulation or a new filename cannot establish which prior transactions were mined. The supplied commands do not resume or redeploy automatically. Avoid sharing provider URLs, private cache files or wallet data.

For a future real deployment, run `make foundry-verify NETWORK=... CONFIG=... MANIFEST=...` before explorer submission. For each actual constructor entry, use `forge verify-contract --chain "$CHAIN_ID" --watch --constructor-args "$ENCODED_ARGS" "$ADDRESS" "$SOURCE:$NAME"` with those exact fields from the verified manifest and the pinned toolchain. This includes the vault-created OpeningQuote and the factory-created ServiceHook. Public cores and externally supplied dependencies retain their original provenance. Configure the explorer API key privately in the environment. Public transaction submission and explorer verification remain unexecuted.

## Executed script evidence, 27–28 November 2026

All nine .s.sol files in the operations table compiled with Forge 1.8.7 and solc 0.8.26, Cancun, via IR and 200 optimizer runs. The deployment and interaction journals contain 47 mined deployment transactions and 66 mined typed actions. The fixture coordinator recorded 36 additional receipts for setup, external trades and the deliberate local payout failure. The ledger identifies the script, selected operation, signer role, status and transaction hash. All hashes are for disposable chains. The fixture coordinator retained hashes and statuses without block numbers in its summary. [Receipt ledger](FOUNDRY-RECEIPTS.csv)

| Chain and close | Deployment / action receipts | Qualifying seconds | Manager paid B | Treasury refund B | Earned reserve held through refund B | Principal received A / B |
|---|---:|---:|---:|---:|---:|---:|
| Local early termination with recipient fault | 12 / 19 | 113 | 37,666,666 | 62,333,334 | 7,666,666 | 2,001,799,918 / 2,001,810,749 |
| Local expiry | 10 / 14 | 287 | 95,666,666 | 4,333,334 | 91,333,333 | 2,001,799,920 / 2,001,810,751 |
| Separate unfunded local cancellation | 10 / 1 | 0 | 0 | 0 | 0 | 0 / 0 |
| Sepolia fork at 68880930, early termination | 9 / 19 | 111 | 37,000,000 | 63,000,000 | 7,000,000 | 2,001,799,918 / 2,001,810,749 |
| Mainnet fork at 64985000, expiry with external stand-ins | 6 / 13 | 287 | 95,666,666 | 4,333,334 | 91,333,333 | 2,001,799,920 / 2,001,810,751 |

Amounts are six-decimal token base units. The runner checked the payer's nonce, actual mined input and sender, deployed bindings, separate funding balances, manager credits, the treasury's actual withdrawal and refund deltas, and the final zero escrow balance. The receipt review also decoded CompensationClaimed, BudgetRefunded and IdleWithdrawn, checked their emitters and indexed recipients, and matched cumulative amounts to the independent balance results. The four funded cases read terms, qualification, opening preview and activation preflight. VerifyDeployment and the terminal settlement reader returned successfully. The terminal reader checked the retired core position directly.

Both early-close cases exercised acceptance reset after a real reference revision, exact approvals, funding, activation, add, remove, rerange, external swap interruption and recovery, checkpoint, claim, termination, exit, withdrawal and refund. Both expiry cases exercised finalizeExpiry. Wrong deployer, wrong chain, wrong actor, stale terms and position, elapsed deadline, incorrect recorded hook flags, a treasury attempt at a manager action and excess liquidity failed before a signer nonce changed.

The local early-close script rejected a blocked claim during Forge simulation. The fixture coordinator separately mined that same typed claim with receipt status 0 and confirmed the paid balance was unchanged. Treasury received both principal assets while the fault remained active. Refunding left exactly 7,666,666 B base units in escrow. Clearing the fault allowed the subsequent Solidity claim to pay that reserve.

The final interrupted mainnet fork log first reported an upstream eth_chainId ReadTimeout after successful compilation. The corresponding Sepolia retry reported ConnectionError at the same read. Both stopped during fork startup. An earlier mainnet rehearsal reached previewOpening and the vault rejected an aged stand-in observation. The recovered runner advances owned blocks deterministically and exercises the stale observation after settlement. The same-pin retries completed with exit 0 on both official cores. The mainnet production-template negative separately rejected the missing reviewed pair and reference. Supplying fork-local external stand-ins exercised the full production code path. Reversed token order, incorrect code identity and stale reference also failed preflight.

Separate unsent script runs on the pinned forks produced a simulated Sepolia draft and the expected mainnet production-template rejection. Each left zero receipts and an unchanged treasury nonce. The retained loopback Make smoke produced distinct simulated and complete v1 manifests, verified the mined draft, read the token symbol through the legacy reader, and mined one typed acceptance. The legacy operator regression printed its completed block-33 reconciliation, including zero remaining rights. The interrupted local and legacy jobs have retained terminal results and journals where applicable. Their original shell exit codes and temporary smoke source were unavailable on recovery. The focused AgreementLifecycle regression passed 11/11, as did the compiled selector inventory, generated viewer artifact check, formatting and signer-routing checks.

Public broadcasts, public encrypted-wallet signing and explorer submissions remain unexecuted. Mainnet requires a reviewed production pair, adapter, source, roles and launch price. Independent A6 reproduction and customer/economic validation remain open.
