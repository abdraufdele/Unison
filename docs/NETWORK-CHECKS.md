# Unichain deployment checks

The supplied C1 configuration uses disposable six-decimal mock tokens and a mock opening source on local and Sepolia fixtures. Mainnet preparation rejects these assets. A mainnet deployment needs a justified pair of ordered exact-transfer tokens and a suitable independent B-per-A opening reference at the C1 scale and freshness bound.

| Network | Chain | PoolManager | Pinned block and hash |
|---|---:|---|---|
| Unichain Sepolia | 1301 | 0x00b036b58a818b1bc34d502d3fe730db729e62ac | 68880930 · 0x1d80409d961d8cea66acd471e44b039f94c82b959247b18bd1a9275e4ce409bc |
| Unichain mainnet | 130 | 0x1f98400000000000000000000000000000000004 | 64985000 · 0xd6c95ae96e4f67c04cb48b7563ba0c4b377554d217cf7d21e4ec773e7fa29b6b |

On 26 November 2026 the official network and deployment tables matched these chain IDs and addresses. The first public RPC attempts returned the pinned headers and deployed code. Runtime keccak was 0x7c5e10e0bd8580e13b48751e4cd7db6315577488d0f76b20bc6c8bcbe2646dc0 on Sepolia and 0x0092eba5db5c7b4a3adbeb5708998d71bd09ad0ab2c299e66ea3f39075e1d249 on mainnet. Both initial behavioral attempts stopped fetching upstream core storage during activation. [Official networks](https://developers.uniswap.org/docs/unichain/technical-information/network-information) · [Official v4 deployments](https://developers.uniswap.org/docs/protocols/v4/deployments)

For the behavior check run `python3 -Bu scripts/ops/network.py fork --network sepolia` or select mainnet. The upstream connection allows chain reads. All fixture submissions go to an owned local Anvil over IPC. The fork check creates fresh mock assets and a real C1 vault, tests a funded preflight, actual activation, external swap, observed tick and treasury recovery on the configured deployed core.

### Executed checks on 27 November 2026

Both pinned behavioral runs exited 0. Each initialized the official core with a fresh fixture pair, transferred both inventories and the separate budget, quoted 598,173,777 base units per leg, installed 100,000,000,000 liquidity, traded to tick 120, observed qualification end and recovered principal with zero position liquidity. Transactions were mined on the owned fork. The public upstream permitted only allowlisted reads. Initial archive-read failures and a nested Forge OP Stack hardfork mismatch interrupted earlier runs. The driver runs its additional Forge constructor rehearsal locally. Both network forks verify actual constructor receipts, sender, runtime and final bindings on their own simulated chain.

| Completed dry run | Simulated receipts | Vault | CREATE2 salt | Full hook init-code keccak |
|---|---:|---|---|---|
| Disposable local | 12 | 0xaA56761C2501d39Bd1bdE6C54CEeFB9a3463149B | 0x928 | 0x3d7feefd3d2449069e457e535da09058a541b55d6ac064084f471c77bec876cd |
| Unichain Sepolia fork | 11 | 0x63A66a64C74F4E5A4C192D2EA39C249628736F78 | 0x4c5b | 0xc5ebcf74d8e03bb4d3742f40b6462c8a2482a6bd057e23250b696b33f1a3b3a6 |

Both manifests verified constructor ownership, the 0x0840 hook mask, pool and recipient bindings. The local receipt count includes deployment of the pinned PoolManager. The config gate rejected mainnet dry-run before opening an RPC connection. Public submission and explorer verification remain unexecuted.
