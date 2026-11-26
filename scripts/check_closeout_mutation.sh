#!/usr/bin/env bash
# Local mutation testing of the two M5 closeout boundaries. The checkout is read-only input.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
case "${1:-}" in
    revocation)
        name=testExactExpiryPreservesCorePositionAgainstManagerRemoval
        assertion='ExpiredPositionChanged\(100000000000( \[1e11\])?, 0\)'
        ;;
    payment)
        name=testExpiredTreasuryReceivesPrincipalWithManagerRouteBlocked
        assertion='PrincipalReceiptShort\(1900054977( \[[^]]+\])?, 1401826223( \[[^]]+\])?\)'
        ;;
    *) echo 'Use revocation or payment' >&2; exit 2 ;;
esac
mkdir -p .local/m5
run=$(mktemp -d "$PWD/.local/m5/$1-XXXXXX")
printf 'Evidence in %s\n' "$run"
compiler=(--offline --use "$HOME/.svm/0.8.26/solc-0.8.26")
selection=(--match-path test/integration/CloseoutBoundary.t.sol --match-test "$name")
forge test "${compiler[@]}" "${selection[@]}" -vv > "$run/baseline.log" 2>&1
grep -F "[PASS] $name()" "$run/baseline.log"
cp -R src test foundry.toml "$run/"
mkdir -p "$run/experiments/m1"
ln -s "$PWD/experiments/m1/vendor" "$run/experiments/m1/vendor"
diff -r test "$run/test"
cd "$run"
python3 - "$1" <<'PY'
from pathlib import Path
import sys
vault = Path('src/AgreementVault.sol')
source = vault.read_text()
if sys.argv[1] == 'revocation':
    old = 'block.timestamp >= scheduledEnd ? State.Expired'
    new = 'block.timestamp > scheduledEnd ? State.Expired'
else:
    old = 'if (liquidity == 0) return;\n        ServiceHook(bindings.hook).stopClock();'
    new = old.replace('ServiceHook(', 'CompensationEscrow(bindings.escrow).claim();\n        ServiceHook(')
assert source.count(old) == 1
vault.write_text(source.replace(old, new))
PY
forge build --root . "${compiler[@]}" test/integration/CloseoutBoundary.t.sol > build.log 2>&1
grep -F 'Compiler run successful' build.log
status=0
forge test --root . "${compiler[@]}" "${selection[@]}" -vvvv > mutant.log 2>&1 || status=$?
test "$status" = 1
grep -Em 1 "\\[FAIL: ${assertion}\\] ${name}\\(\\)" mutant.log
if [[ $1 == revocation ]]; then
    grep -Eq 'emit PositionAdjusted\(.*liquidity: 0,' mutant.log
else
    # Limit the payment check to the exit subtree, after the initial intentionally failed claim.
    sed -n '/AgreementVault::exitLiquidity()/,/AgreementVault::withdrawIdle()/p' mutant.log > exit.log
    grep -Eq 'CompensationEscrow::claim\(' exit.log
    grep -Eq 'blocked route' exit.log
    grep -Eq 'TransferFailed\(' exit.log
fi
printf 'Baseline and mutation build exited 0. Mutated test exited %d.\n' "$status"
