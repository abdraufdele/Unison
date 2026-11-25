# M1 replay on native WSL · 23 November 2026

The original suite and corrected assessment passed on x86-64 WSL2. The isolated omitted-checkpoint variant compiled and failed the intended full-removal assertion. The replay used source from development revision `4e81e75` and the local Forge test EVM. All five imported files passed their recorded SHA-256 checks before and after execution. [Imported hashes](SHA256SUMS)

| Run in execution order | Files compiled | Passed | Failed | Skipped | Native Forge exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original ExperimentTest, including 128 seeded fuzz runs of 32 steps | 47 | 19 | 0 | 0 | 0 |
| AssessmentTest, restricted to the six corrected assessment cases | 48 | 6 | 0 | 0 | 0 |
| Isolated ExperimentTest, full-removal case only | 47 | 0 | 1 | 0 | 1 |

The variant used its own source, tests, output and cache. Its test file matched the original byte for byte. The only source change was omission of the vault's pre-change checkpoint. The same full-removal test passed in the unchanged suite. The variant log contains these lines from compilation and execution:

```text
Compiler run successful!
[FAIL: full removal must preserve old 100 seconds] testFullRemovalCheckpoint() (gas: 238370)
```

## Payment reconciliation

The assessment trace started at timestamp 1000 with a qualifying seed. At 1100 the outward swap reached tick 180 and stored 100 qualifying seconds. At 1200 the return swap reached the tick-0 target price with stored tick −1. Qualification resumed and the accumulator still held 100 seconds. The final interval through 1300 added another 100 seconds.

A third-party claim transferred **200 × 10¹⁸ base units** to the fixed manager. The caller received zero. Of the initial 300 tokens, 200 were paid and 100 remained in escrow. A repeat claim at 1500 left both balances unchanged. The experiment has no supported refund for that remainder.

## Reproduction and evidence

| Verified input | Value used |
| --- | --- |
| Native Forge | 1.8.7, commit `985eeea031d79922cd654d4e94e6c3701e1c7d73` |
| Native solc | 0.8.26+commit.8a97fa7a.Linux.g++, SHA-256 `d5f23436f443edb85d8e76906d12f0a86ce0490e7663a9e608efeb7a93f149ef` |
| Uniswap v4-core | `e50237c43811bd9b526eff40f26772152a42daba` |
| Solmate | `4b47a19038b798b4a33d9749d25e570443520647`, equal to the core gitlink |
| Effective default profile | Cancun, optimizer on with 200 runs, via-IR on, dynamic test linking and FFI off. Gas limit 1,000,000,000 and code-size limit 200,000. Fuzz seed `0x19112026`, 128 runs. |

The full-history GitHub clone was stopped during a slow transfer (exit 143). Its destination was absent before retry. This run obtained clean dependency checkouts from existing local Git object stores at the two pinned commits. Only Solmate was initialized. The upstream notices were retained. To reproduce that setup with an existing clean reference, set `M1_CORE_REFERENCE` to its v4-core checkout with the pinned Solmate submodule present, then run from `experiments/m1/` with a new vendor destination:

```bash
set -eu
test "$(git -C "$M1_CORE_REFERENCE" rev-parse HEAD)" = e50237c43811bd9b526eff40f26772152a42daba
test "$(git -C "$M1_CORE_REFERENCE/lib/solmate" rev-parse HEAD)" = 4b47a19038b798b4a33d9749d25e570443520647
git clone --no-hardlinks --no-checkout "$M1_CORE_REFERENCE" vendor/v4-core
git -C vendor/v4-core checkout --detach e50237c43811bd9b526eff40f26772152a42daba
git -C vendor/v4-core -c protocol.file.allow=always \
  -c "submodule.lib/solmate.url=$M1_CORE_REFERENCE/lib/solmate" submodule update --init -- lib/solmate
git -C vendor/v4-core submodule init -- lib/solmate
```

The [replay procedure](REPLAY.md) gives the alternative upstream checkout, pin and clean-tree checks, and the three Forge commands executed here. There were no inherited Foundry or DappTools configuration overrides. Each run set the default profile, used the cached compiler explicitly and ran offline. The assessment supplied its test directory and relative remappings. The mutation supplied its isolated directory overrides. A local recorder redirected stdout and stderr directly to files and saved each native exit code.

Private evidence is under `evidence/wsl-KhKdxlFQ/` relative to this directory. It includes commands, selected settings, dependency identities, native exit codes and the full logs. SHA-256 fingerprints identify the retained outputs.

| Private log | SHA-256 |
| --- | --- |
| `original.txt` | `b31a7fa4e659a19fb2b6f9e9891c0227f4d69e3d277e9fd319dbb979816777f7` |
| `assessment.txt` | `4d1a64a32ea95077bc404b05b2f58634c0905547188c9f841c7b3ea4bdf43209` |
| `mutant.txt` | `e3be991e8c333931e8e156295e41c1a15941804ecf7fafc9f1b473f9002349a4` |

The archived Windows run and this WSL run agree on suite outcomes, return tick, payment, residual and mutation assertion. The WSL original suite also measured incremental execution gas of **97,462 outward**, **57,636 on return** and **26,904 after termination**, matching the three Windows samples. These are path-specific measurements. C1 acceptance and funding, earned reserves, refunds and exit under payment failure still need their own engineering evidence. Customer acceptance, total-cost advantage and production security remain unverified. [M1 scope and Windows evidence](../../docs/M1-STATUS.md)
