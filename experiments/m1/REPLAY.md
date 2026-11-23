# Pinned WSL setup and M1 replay

Run these steps **during the next setup/replay task** in Bash on WSL. This import session checked binaries, config, hashes and archive records. Linux compilation, dependency checkout and test results are pending. Use a local Forge test EVM with no RPC, wallet, broadcast or Anvil process.

## Tools and inputs

The inspected host is x86-64 WSL2, Ubuntu 24.04.3. Native Forge, Cast, Anvil and Chisel report 1.8.7 at `985eeea031d79922cd654d4e94e6c3701e1c7d73`. Forge is the only one needed. Git 2.43.0, Python 3.12.3 and GNU sha256sum are available. Use the existing SVM-cached native Linux solc directly. The bare `solc` on PATH is a solc-select wrapper that attempted a latest-version lookup during inspection and failed. It installed nothing. The cached binary reports 0.8.26+commit.8a97fa7a and matches the official Linux AMD64 digest. It has a different digest from the preserved Windows compiler. [Solidity release manifest](https://raw.githubusercontent.com/ethereum/solc-bin/gh-pages/linux-amd64/list.json)

Start at the Unison repository root in a single Bash session. These commands verify the inputs before any compilation. The dependency setup below assumes a new `vendor/v4-core` destination. On a retry, keep an existing checkout and verify its commits and cleanliness before reuse.

```bash
set -euo pipefail
cd experiments/m1
export FOUNDRY_PROFILE=default NO_COLOR=1
m1_solc=~/.svm/0.8.26/solc-0.8.26
m1_core=e50237c43811bd9b526eff40f26772152a42daba
m1_solmate=4b47a19038b798b4a33d9749d25e570443520647
sha256sum -c SHA256SUMS
forge --version | grep -F '985eeea031d79922cd654d4e94e6c3701e1c7d73'
"$m1_solc" --version | grep -F '0.8.26+commit.8a97fa7a.Linux'
printf '%s  %s\n' d5f23436f443edb85d8e76906d12f0a86ce0490e7663a9e608efeb7a93f149ef "$m1_solc" | sha256sum -c -
```

Fetch only v4-core and its pinned Solmate submodule. There is no forge-std, periphery, Node, Rust or system package installation in this setup. The archived config already declares both dependency remappings.

```bash
git clone --no-checkout https://github.com/Uniswap/v4-core.git vendor/v4-core
git -C vendor/v4-core checkout --detach "$m1_core"
test "$(git -C vendor/v4-core rev-parse HEAD:lib/solmate)" = "$m1_solmate"
git -C vendor/v4-core submodule update --init -- lib/solmate
test "$(git -C vendor/v4-core rev-parse HEAD)" = "$m1_core"
test "$(git -C vendor/v4-core/lib/solmate rev-parse HEAD)" = "$m1_solmate"
test -z "$(git -C vendor/v4-core status --porcelain)"
test -z "$(git -C vendor/v4-core/lib/solmate status --porcelain)"
```

## Replay and record

Run from the same directory. Store raw outputs in the ignored `evidence/` directory. Inspect the effective config for Cancun, optimizer enabled with 200 runs, via-IR enabled, dynamic test linking and FFI disabled, fuzz 128 with seed 0x19112026, gas limit 1,000,000,000 and fixture code-size limit 200,000. Resolve any environment overrides before running. Keep the independent assessment out of the original benchmark's source graph.

```bash
mkdir -p evidence
m1_evidence=$(mktemp -d evidence/wsl-XXXXXXXX)
forge config --root . --json > "$m1_evidence/config.json"
forge test --root . --offline --use "$m1_solc" --match-contract '^ExperimentTest$' -vv \
  > "$m1_evidence/original.txt" 2>&1
grep -F '19 passed; 0 failed; 0 skipped' "$m1_evidence/original.txt"

FOUNDRY_TEST=assessment forge test --root . --offline --use "$m1_solc" \
  -R 'original/=test/' -R 'experiment/=src/' \
  -R 'v4-core/=vendor/v4-core/' -R 'solmate/=vendor/v4-core/lib/solmate/' \
  --match-contract '^AssessmentTest$' --match-test '^testAssessment' -vvvv \
  > "$m1_evidence/assessment.txt" 2>&1
grep -F '6 passed; 0 failed; 0 skipped' "$m1_evidence/assessment.txt"
```

For the historical mutation control, keep a separate source and test copy under the experiment root. The variant uses the existing dependency tree. The test's relative import resolves to the variant source. Keep its outputs and cache separate. Require the exact assertion and a single failed test after the unchanged suites pass.

```bash
m1_variant=$(mktemp -d mutation-XXXXXXXX)
cp -R src test "$m1_variant/"
python3 - "$m1_variant/src/Experiment.sol" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_bytes()
checkpoint = b'if (address(hook) != address(0)) hook.checkpoint(); // MUTATION_TARGET'
assert source.count(checkpoint) == 1
path.write_bytes(source.replace(checkpoint, b'// omitted pre-change checkpoint'))
PY
m1_exit=0
FOUNDRY_SRC="$m1_variant/src" FOUNDRY_TEST="$m1_variant/test" \
  FOUNDRY_OUT="$m1_variant/out" FOUNDRY_CACHE_PATH="$m1_variant/cache" \
  forge test --root . --offline --use "$m1_solc" --match-contract '^ExperimentTest$' \
  --match-test '^testFullRemovalCheckpoint' -vv > "$m1_evidence/mutant.txt" 2>&1 || m1_exit=$?
test "$m1_exit" -eq 1
grep -F '[FAIL: full removal must preserve old 100 seconds] testFullRemovalCheckpoint()' "$m1_evidence/mutant.txt"
grep -F '0 passed; 1 failed; 0 skipped' "$m1_evidence/mutant.txt"
sha256sum -c SHA256SUMS
```

Record actual versions, test counts, exit codes, the timeline’s seconds, paid and residual amounts, and the individual swap measurements. Retain failures privately and explain any platform difference before using a Linux result as evidence. The target Windows timeline was 200 qualifying seconds, 200 tokens paid and 100 left in escrow. Only a completed WSL replay can supply a Linux result.
