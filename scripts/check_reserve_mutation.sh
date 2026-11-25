#!/usr/bin/env bash
# Reproduce the reserve regression using the unchanged product integration test.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mkdir -p .local/m4
run=$(mktemp -d "$PWD/.local/m4/reserve-XXXXXX")
printf 'Reserve evidence in %s\n' "$run"
compiler=(--offline --use "$HOME/.svm/0.8.26/solc-0.8.26")
case_name=testTerminalRefundLeavesUnpaidEarnedReserve
case_args=(--match-path test/CompensationSettlement.t.sol --match-test "$case_name" -vv)
forge test "${compiler[@]}" "${case_args[@]}" > "$run/baseline.log" 2>&1
grep -F "[PASS] $case_name()" "$run/baseline.log"
cp -R src test foundry.toml "$run/"
mkdir -p "$run/experiments/m1"
ln -s "$PWD/experiments/m1/vendor" "$run/experiments/m1/vendor"
diff -r test "$run/test"
cd "$run"
test "$(grep -Fc 'return fundedBudget - totalEarned - refunded;' src/CompensationEscrow.sol)" = 1
sed -i 's/return fundedBudget - totalEarned - refunded;/return fundedBudget - claimed - refunded;/' src/CompensationEscrow.sol
forge build --root . "${compiler[@]}" test/CompensationSettlement.t.sol > build.log 2>&1
grep -F 'Compiler run successful' build.log
status=0
forge test --root . "${compiler[@]}" "${case_args[@]}" > mutant.log 2>&1 || status=$?
test "$status" = 1
grep -E "\\[FAIL: ReserveStolen\\(20000000( \\[2e7\\])?, 0\\)\\] ${case_name}\\(\\)" mutant.log
printf 'Baseline and mutant build exited 0. Mutated test exited %d.\n' "$status"
