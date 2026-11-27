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

All four commits were selected from the already-pinned v4-core revision or its recorded upstream gitlinks, not arbitrary latest releases. Root gitlinks are authoritative. `make prerequisites` checks all four pins and clean library worktrees as well as the preserved M1 import hashes. Do not upgrade libraries as part of a layout change.

```bash
git submodule update --init -- lib/v4-core lib/solmate lib/forge-std lib/openzeppelin-contracts
forge remappings
make prerequisites
make build sizes test
make artifacts viewer-build
```

Automatic remapping discovery is disabled. Root `remappings.txt` explicitly resolves v4-core, Solmate, forge-std and `@openzeppelin/contracts/`. Mutation sandboxes copy this file and link the root `lib/`. The historical M1 foundry.toml, hashes and vendor checkout remain untouched; follow its own replay procedure separately. Do not commit generated output, caches, broadcasts or private manifests.

Moving source paths changes compiler metadata and CREATE2/build identities even when executable behavior is unchanged. Regenerate current artifacts and mine new hook addresses for future deployments. Historical runtime/gas evidence remains tied to its original revision.
