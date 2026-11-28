# Active Foundry dependencies and layout

The active project follows the conventional root layout also used by [POINCARE](https://github.com/Prakhar-30/POINCARE): `src/`, `script/`, `test/`, `lib/`, `foundry.toml` and `remappings.txt`. This adopts organization only; no competitor mechanism or implementation was copied.

- `src/`: Unison contracts, interfaces and focused math/token helpers.
- `script/`: Solidity deployment and agreement rehearsal scripts.
- `scripts/`: operator commands, verification, mutation runners and browser tooling.
- `test/unit`, `test/integration`, `test/fuzz`, `test/invariant`: the active test categories; shared fixtures and helpers remain separate.
- `lib/`: pinned upstream Git submodules, visible on GitHub through `.gitmodules` and root gitlinks.
- `config/`: network configuration; private operator overrides stay ignored.
- `viewer/`: the contract-backed frontend and its package lock.
- `docs/`: specifications, evidence and runbooks.
- `experiments/`: separately preserved historical/research work, not the active dependency location.

## Pins, scope and licenses

- v4-core: `e50237c43811bd9b526eff40f26772152a42daba`, https://github.com/Uniswap/v4-core. Active protocol dependency; file-specific BUSL-1.1/MIT notices apply.
- Solmate: `4b47a19038b798b4a33d9749d25e570443520647`, https://github.com/transmissions11/solmate. Active v4 dependency. Preserve file-specific notices, including Owned's AGPL-3.0-only notice.
- Forge Standard Library: `1de6eecf821de7fe2c908cc48d3ab3dced20717f`, https://github.com/foundry-rs/forge-std. Available development/testing library; no claim that Unison inherits Test or Script. Existing narrow cheatcode interfaces remain unchanged. Upstream provides MIT/Apache-2.0 licensing.
- OpenZeppelin Contracts: `dbb6104ce834628e473d2173bbc9d47f81a9eec3`, https://github.com/OpenZeppelin/openzeppelin-contracts. Available MIT-licensed library requested for the project layout; currently not imported by Unison product code. Its presence is not an integration or security guarantee.
- Safe smart account v1.4.1: `bf943f80fec5ac647159d26161446ac5d716a294`. Test-only dependency from the Safe team. SafeL2, SafeProxyFactory, SafeProxy and CreateCall retain upstream copyrights and file-specific license notices, including LGPL-3.0-only. The gitlink preserves corresponding source and the upstream license. [Official release source](https://github.com/safe-global/safe-smart-account/tree/bf943f80fec5ac647159d26161446ac5d716a294) · [Upstream license](../lib/safe-smart-account/LICENSE)

`make init` restores the five gitlinks and four official Safe Hardhat artifacts into the ignored `.local/safe-release` directory. The original release archive is `@safe-global/safe-contracts@1.4.1`. Its npm gitHead matches the Safe gitlink. The bootstrap verifies the archive SHA-512 and the SHA-256 of each extracted JSON. It runs no package scripts. For offline provisioning, provide a previously downloaded archive to `python3 -B scripts/prepareSafeRelease.py --archive PATH`. The C1 compiler settings apply to the test caller. The fixture deploys the upstream creation bytes and checks each runtime. [Artifact pins and restore command](../scripts/prepareSafeRelease.py)

The release build-info records solc `0.7.6+commit.7338295f`, Istanbul, optimizer disabled (runs field 200), and literal source content in metadata. All 43 packaged Solidity sources matched the pinned checkout. These keccak256 values cover the release bytecode before constructor arguments and the deployed runtime template. The proxy factory appends the selected singleton to the proxy creation bytes. The resulting proxy stores the singleton address in storage. The local test verifies the four deployed runtime hashes and separately reads the proxy's master copy.

| Official contract | Creation keccak256 | Runtime keccak256 |
|---|---|---|
| SafeL2 | `0x3555bd3ee95b1c6605c602740d71efaf200068e0395ccd701ac82ab8e42307bd` | `0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff` |
| SafeProxyFactory | `0x596f87ec561ad5ea1c13253af5c91247a713253499b74a5d594537cae42eaaa9` | `0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317` |
| SafeProxy | `0x1856e0ee08399d74e0ea0b03adca210aeade6f748969ac023cdcb4dd62dcaf5f` | `0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c` |
| CreateCall | `0x0871bf92dc4e13f2fd05dfec9570999908913bb89dda487f781cebe3435f9c62` | `0x2b3060c55fcb8275653e99ad511a71f67ba76934ed66a7d74d6e68b52afff889` |

Root gitlinks are authoritative for source. `make prerequisites` checks all five pins, tracked library cleanliness, the four original release artifact hashes and the preserved M1 import hashes.

```bash
make init
forge remappings
make prerequisites
make build sizes test
make artifacts viewer-build
```

Automatic remapping discovery is disabled. Root `remappings.txt` explicitly resolves v4-core, Solmate, forge-std and `@openzeppelin/contracts/`. Mutation sandboxes copy this file and link the root `lib/`. The historical M1 foundry.toml, hashes and vendor checkout remain untouched; follow its own replay procedure separately. Do not commit generated output, caches, broadcasts or private manifests.

Moving source paths changes compiler metadata and CREATE2/build identities even when executable behavior is unchanged. Regenerate current artifacts and mine new hook addresses for future deployments. Historical runtime/gas evidence remains tied to its original revision.
