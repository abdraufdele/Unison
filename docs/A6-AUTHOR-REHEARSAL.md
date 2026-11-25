# A6 clean-checkout author rehearsal

On 25 November 2026 the author ran two rounds of three browser journeys against public development commit `eb4922d6a344987f6b041933bb0ce34ac9c6902d`. All six deployments used disposable local Anvil and mock assets. The 52 action receipts and 16 statement downloads reconciled. This was a clean checkout on a provisioned host. Independent developer reproduction remains pending.

## Setup and deviations

| Item | Actual environment or observation |
| --- | --- |
| Source | Fresh upstream development clone in a new temporary directory. Clean Git status at entry and exit. No working-checkout dependencies, compiler output, manifests, credentials or local configuration were copied. |
| Host | Ubuntu 24.04.3 LTS, WSL2 Linux 6.18.58.1, x86-64. Git 2.43.0, Python 3.12.3, installed Web3.py 7.13.0, rlp 4.1.0 and eth-utils 5.3.1. Python provisioning from an empty machine was outside this run. |
| Solidity | Forge/Anvil 1.8.7 at `985eeea031d79922cd654d4e94e6c3701e1c7d73`. Installed native solc 0.8.26+commit.8a97fa7a matched its documented SHA-256. The viewer build compiled 58 files in 57.57 s using Cancun, via IR and optimizer 200. Artifact verification passed and regenerating the ABI produced no tracked diff. |
| Upstream source | The documented full v4-core clone exceeded the 180 s rehearsal timeout. The shallow fetch of `e50237c43811bd9b526eff40f26772152a42daba` succeeded. The Solmate gitlink and checkout matched `4b47a19038b798b4a33d9749d25e570443520647`. Both dependency trees were clean. All five M1 hashes passed before and after. |
| Frontend | Node 22.19.0, npm 11.21.3. The documented `npm ci` installed 34 packages using the public lockfile and existing npm cache. TypeScript and Vite 6.4.3 production builds passed. npm reported one moderate and two high advisories. Dependencies and lockfile were kept at the rehearsed pins. |
| Browser | The documented Playwright download exceeded the 180 s limit. The author fetched the **same** official Linux x64 build 1193 in non-overlapping byte ranges, checking range, length and ETag. The assembled ZIP passed integrity checks and had SHA-256 `7d93c385edba3ac9f10f13037e600353f29f84691f09d26b935bfc117bbceb98`. The browser identified itself as Chromium 140.0.7339.186. The runbook now documents this archive for its existing `CHROMIUM_PATH` option. |
| Services | Before launch, neither host demo port had a listener. No original launcher or Anvil was visible, and the historical block-27 endpoint refused connection. Its current live identity could not be reverified. The rehearsal used a private Linux user/network namespace with loopback enabled and the documented 5173/18547 ports. Each reset stopped only the launcher's own child. The rehearsal launcher, Vite, Anvil and Chromium exited. No host service was reset, stopped or replaced. |

The opening grid and source-format checks passed. The source and package licenses stayed with their pinned dependencies. The unchanged product suite retains its prior 115-test result. The two download timeouts describe this host and the chosen bounds. [Setup commands and dependency fallback](LOCAL-VIEWER.md#start-inspect-and-stop) · [Upstream attribution](../experiments/m1/README.md#attribution-and-license-scope)

## Financial results observed in both rounds

Amounts below use six-decimal mock tokens. **Paid** means the manager received B. **Refunded** means the treasury received B from escrow. Treasury principal withdrawals are separate.

| Path and point | Q | Earned B | Paid B | Refunded B | Reserved B | Refundable B | Escrow B |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Every funded opening, block 22 | 0 | 0 | 0 | 0 | 0 | 0 | 100 |
| Manager path after withdrawal, block 30 | 180 | 60 | 0 | 0 | 60 | 40 | 100 |
| Interruption/recovery after termination, block 27 | 120 | 40 | 0 | 0 | 40 | 60 | 100 |
| Payment failure after termination, block 30 | 180 | 60 | 40 | 0 | 20 | 40 | 60 |
| Payment path after refund, block 34 | 180 | 60 | 40 | 40 | 20 | 0 | 20 |
| Payment path after restoration and zero-value retries, block 38 | 180 | 60 | 60 | 40 | 0 | 0 | 0 |

- **Manager.** The seed returned 598.173776 A and B each. Reopening at [−180, 180) used 895.917529 of each, preserved 100,000,000,000 L on salt 2 and left 1,104.082470 of each idle. The 700 B order spent 603.584180 B for 598.173776 A. Tick 120 continued to qualify. Terminal removal returned 297.743752 A and 1,497.690955 B principal plus 1.810752 B LP fees. Including idle assets, the treasury received 1,401.826222 A and 2,603.584177 B.
- **Interruption.** Tick 120 suspended service at Q=90. Tick −1 restored qualification at the same Q. The next 30 seconds took Q to 120. At termination 100,000,000,000 L was still invested, the vault held 1,401.826223 A and B each, and neither closeout principal nor fees had been withdrawn.
- **Payment failure.** The manager received the initial 40 B at Q=120. Both runs produced `TransferFailed(address)` for the blocked second claim and `InvalidPeriod()` for a manager removal after termination. The same removal had succeeded in a pre-close simulation. With payment blocked, the vault received 698.218788 A and 498.228754 B principal plus 0.301038 A LP fees. The treasury withdrew 2,100.346049 A and 1,900.054977 B, then received 40 B from escrow. Restoring the route paid the manager exactly 20 B. Both eligible retries transferred zero.

## Browser and identity checks

Each round began with a fresh funded manager run. Explicit resets naming the full current run ID separated manager, swap and payment paths and the two rounds. At all five replacements the funded anchor and onchain ID changed. The old action with its old token returned HTTP 403. The old run ID with the new token returned HTTP 409. Serving the old public manifest to the replacement page showed the stale-deployment error and cleared the controls.

A private test driver clicked the built page. Each receipt was checked against its mined block, sender, target, hash and expected outcome. Downloads covered the funded and final state on all six paths, plus payment termination and post-refund state in both rounds. Each JSON matched the displayed block and run and contained both acceptance events. Its event-derived ledger agreed with contract reads and separate viem escrow reads at the same block. Loading, refreshing the funded view and downloading left the applicable head unchanged. There were no uncaught browser page errors. Full statements and raw diagnostics remained outside Git.

Both rounds matched on interval timing, ordered event names, escrow rights, token custody, principal and fee amounts. Random accounts and agreement markers changed addresses, terms and transaction/block hashes. Gas equality was outside the comparison. Deployment work such as CREATE2 salt selection can vary by run. All evidence comes from a local provider. In M6 the bounded retainer delivered the same tested liquidity. The 40 B refund reallocates the compensation budget. A1/A2/A3 still require customer and economic evidence.

## Run identities and receipts

All deployments used chain 31337. The funded anchor is block 22. The end hash identifies the downloaded final statement's as-of block.

| Round | Path | Run / agreement ID | Funded anchor hash | End block / hash |
| ---: | --- | --- | --- | --- |
| 1 | manager | `0x0e15921c65accf9959a1b1fe4ab3afc376890451658d9f04fc6fc91c00576bc4` | `0xb49dfe7befbe521eedd2dac451e158d225891c80da29e7fa6940b717c471962f` | 30 / `0x773147010da1e06155f8bf0c3e4d5e39d4e47ca525f28b4dd5a88caf47c48262` |
| 1 | swap | `0x98e2a246979302f2378772796704137b7e879bc1c5d1671d4d50a52bb18f0680` | `0xea8807f009ec45025cf8fee9f71ea8c9a679ccc6c60a1d9ef9904c2211a9105c` | 27 / `0x1b72809ef9d10d1047c7873de795f0cca6fdbdde8fcd380d140a089cc30fcc30` |
| 1 | payment | `0x805ac3f193567acf6b7261598f2e45ad6b66b3cdf4224fd9164c39615ab6bf60` | `0xdbbee71372093021a1bdb951743f2596ae212497e561011eeed2491889a78d31` | 38 / `0x564aed8222f476b0a2ff0e238ff8101b8b6df78fc407d525088ed6f49a3dae69` |
| 2 | manager | `0x459886e70f6380206c62887ee45124ed2c57a16648f8db258450946b0077a128` | `0xc90844b4e7cdc26edc42aaca3031391374dd45a2754669fd8312fdb87f8b61d7` | 30 / `0x97d02db9f8c6d804be5b2aec184cd8dafb9aee7d99ce9da52374a84b4c2025f0` |
| 2 | swap | `0x25a07e1a38266333b35779b480ff5071f54d91c8616f8085de2d10cfb4403673` | `0x7561cf433be8b8c87135c77fa1d747f3ee11c2b58f5391da3c834e7406b8eb2d` | 27 / `0xe47e86a9d771d8820e652490d2791e042eb2596e5e885c0edc5f2f06bccf6ee7` |
| 2 | payment | `0x57f9967fd8f35aeb03635795eeab2c8eee69fd9d31011cf82fda2ef1406c69f3` | `0x03fe9e4a114f2ed7a321e06532466b74a47bf0fa6a1afb7d5d502a752aa2570b` | 38 / `0xc972ae4c2a2bfe3cce5189b43c284237efde2e50261950f8fdfa8abb55226225` |

Each row below is a mined action in each of the two runs for that path. The two expected reverts per payment path are marked explicitly.

| Path | Action | Block | Outcome | Round 1 transaction | Round 2 transaction |
| --- | --- | ---: | --- | --- | --- |
| manager | activate | 23 | Mined | `0x4ab5de8c8d377581db19c649719414bd49252c88524420fe247e349705feccd0` | `0x1c44c456bf67015ba0ecec30e63aee2e7752b024171af8a42cf8136deee04d4e` |
| manager | prepareRange | 25 | Mined | `0xe50e0ef04531764cfdd3c21e33135515e3b6130c41011c098c0ea230e5f83ee0` | `0xb14c689bfe194d27613527d3b352827b0ab83703e1bad28bd4da0cb937c340a5` |
| manager | rerange | 26 | Mined | `0x6e63931e6064472ad582140441e28b0e5cbc10743cbe2f01015c86bc6b85405b` | `0x5167fb4aa6976887ced09c73a6090ee3cbbeeadaaee1e4ae5f7ea13e49fac2fa` |
| manager | rangeSwap | 27 | Mined | `0x9f34fafdb7aa1e3d36db8304c3d585e0a53ca48c2a4f5b6089cbe7a6f212e260` | `0x35256874e3514ec16ee776ed75326a028f54590975681914266adbc3e48e2b89` |
| manager | rangeClose | 28 | Mined | `0xc596eea3123bd2aba0b5c0162b7e9f7d80f23b978bfe78361f25034377955042` | `0x283f36c1bb2602a3fc01260d6953164736c5e3558242f7dc0e98ef86eb4898ff` |
| manager | rangeExit | 29 | Mined | `0x75ba59a47a2e4c2fafd5454b2e3930341fa6bbdaa51395014b2ae735a1bad5d2` | `0x0c92bdc7d3ca420e4c24430e9b3045d5ebd11471241caed9467fcbc731e5c3e1` |
| manager | rangeWithdraw | 30 | Mined | `0x4a6a509adebcba0708829d53b7d8d97da32d4a6f660f46649f7b2eca67e520eb` | `0xc6dde12518dea43d42a7c98fae7d833ae17c23be142c0ac918309a4ea55b3bdd` |
| swap | activate | 23 | Mined | `0xbd80698e465c076208e605dce521273b55d8e570ec0756395d9f060348ad47a9` | `0x25de386872f33fa6a63d9abc9bebc485e64b9bc21c1b31b4b5e0227acbe2d1ca` |
| swap | interrupt | 25 | Mined | `0x0edb4b1c09ee9b2d1173df1e21bac5b510c5db989b6ce82acf65f6cab2bc69b1` | `0xcb13f22bb4fbff95ad1c4278ba2a6f5230a7ceff6e0e06272d40363964c61465` |
| swap | return | 26 | Mined | `0xbf5586f53bf63f45ae6c86421fb3e897b2714bf241480353e0e31e063454f231` | `0x9be96551686f33c012d941cc9587f532a0cb673ca897306befd6bc50ca717aba` |
| swap | returnClose | 27 | Mined | `0xa6fec5d590c7362f3eb5effe9ad93539e29cbf7e421c401330efe4a5ff903571` | `0x207b224b7c569dd45fb20cc204732ec4da987296151b9760cd0524f8a95decb3` |
| payment | activate | 23 | Mined | `0xfcb56a2077ed947cf9c85e9ffdf8129629339c197278bd6e3f4dfb12ed7c9bd4` | `0x2475c7e9e47fd39f1a0b366cb9b2c4e55e6a4633fa4164760e028f7ad02fda20` |
| payment | trade | 25 | Mined | `0x8ca681bbb3d14e0aac3f2d55bfa68c60a4f4207ab05514e1d1180d2f4828f5ac` | `0x1936e8fcd661f858d57377767c5e7442679af34ab43f55a6e30ef3f6c971fb6b` |
| payment | claim40 | 26 | Mined | `0xa0987b4ad3259c30c4bf379b77276e1834eb8f501613e4d0571fa096d40bead1` | `0x7945397a8bc2d9dad04d4d27ba141fc6203fab3b57835082a76cfacb580af79d` |
| payment | checkpoint | 27 | Mined | `0xa08eeb0e7bb1078136b151f008ca4b1433bbba8288a7e7feb79b131395cbba9a` | `0x831183b1a0aa277da5e8f413ad06a92ba36ac69793a5370082668820498be44d` |
| payment | block | 28 | Mined | `0x91a1c0af6062b739f0ed62176555017507ecc3b2ee9ba231a99d4bdfa0616193` | `0x6e9a4d2c036c47078fb5c516ed0f974b3786781f3797831cb9bca6c24ad8e9f8` |
| payment | failedClaim | 29 | Reverted · `TransferFailed(address)` | `0x620d6e188cd12a97f2901d5b523c2835dd40962608c1d8a55b36e28e42775d5e` | `0xfcc5918af3141fa05f44e097ea033288e80b7be17bb3a284a6dbbea3c7207d65` |
| payment | terminate | 30 | Mined | `0xb5a3ddbc8ca615c3812401ecfac799ea34bb013413a6dbbdf7b63c8a860a6c6a` | `0xef88d13b0501d629de59b621076833be2619d2113b55e02dc46e3a4c56a91ccd` |
| payment | revoked | 31 | Reverted · `InvalidPeriod()` | `0x9dcfb33fda7274fc13013b9baf916e3e9efd7812c0af8621fae664a0d27241ac` | `0x2ee48e727474b5a7f03cbfe74aa5f75416676d6bb8ce75c0098f52efed45039d` |
| payment | remove | 32 | Mined | `0x0d18382e77990c4eb5206dc8fbca0eafc0b66306926e45b5f94b1bc014947eb1` | `0x96dd7ca52737b6957a8dde833b0d39e6c4e7f5458cd1e3204bc5cc8eb19a95f6` |
| payment | withdraw | 33 | Mined | `0xeb9a0177f97a840a2f3d9202b242047128902d5f65fe17cdf45e626a10d003fb` | `0x2f53bccd1fe8591d2816eed94762ef0af6c35eb15733210e00797057af871d19` |
| payment | refund | 34 | Mined | `0x1625377eb1bdc204db47c9303e2ad025cb8bc4ac2062df39951a028e65024b23` | `0xdd89ceb14013a0710c79fd94cb4a7169e6f8f1b112a3f6f73e35d71f1fe82e32` |
| payment | restore | 35 | Mined | `0x69a893b999f46bba43d8a826fa3c8e636592806234d7a5c97d293accdbcbe574` | `0x6f37b83c1a85cd3c740564d1f226b0259285c5fe53b61cd2c03b847fe925e3d0` |
| payment | claim20 | 36 | Mined | `0xc2d6411e0e63da5e2098b38dd5061cf6070be44ef493aba1054c19ba1743fd91` | `0xa2d021219718d01dcbd5129741bda541d8aaee6b324ccce994d6f48e16b55a20` |
| payment | repeatClaim | 37 | Mined | `0xbb2dc4101f1fbee8ec93da7587bc710c10156ee12ef0cfd5dde3b083220642fd` | `0x3e76602bc5fadea58edc6114dc2152537b074d3d6e654a7cd711fc527f2908ac` |
| payment | repeatRefund | 38 | Mined | `0x91933e08431985ccddba46bcb185b04f225171c1f77ed25e121d7c26f6e75152` | `0xa49a54ac80d8f012b32aa24bf7e2bdcfcd7418c9b8c287c6ce077d7bbee8db07` |
