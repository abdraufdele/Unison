#!/usr/bin/env bash
# Re-run the identical real-core full-removal test before and after omitting the old checkpoint.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mkdir -p .local/m3
run=$(mktemp -d "$PWD/.local/m3/order-XXXXXX")
printf 'Clock ordering evidence in %s\n' "$run"
forge_args=(--offline --use "$HOME/.svm/0.8.26/solc-0.8.26")
test_args=(--match-path test/integration/ServiceClock.t.sol --match-test testFullRemovalPreservesOldIntervalAndReopeningUsesFreshSalt)
forge test "${forge_args[@]}" "${test_args[@]}" -vv > "$run/baseline.log" 2>&1
grep -F '[PASS] testFullRemovalPreservesOldIntervalAndReopeningUsesFreshSalt()' "$run/baseline.log"
cp -R src test foundry.toml remappings.txt "$run/"
ln -s "$PWD/lib" "$run/lib"
test "$(grep -F -c 'ServiceHook(bindings.hook).beforeAdjustment();' "$run/src/AgreementVault.sol")" = 1
sed -i '/ServiceHook(bindings.hook)\.beforeAdjustment();/d' "$run/src/AgreementVault.sol"
diff -ru test "$run/test"
cd "$run"
forge build --root . "${forge_args[@]}" test/integration/ServiceClock.t.sol > build.log 2>&1
grep -F 'Compiler run successful' build.log
status=0
forge test --root . "${forge_args[@]}" "${test_args[@]}" -vv > mutant.log 2>&1 || status=$?
test "$status" = 1
grep -F '[FAIL: OldIntervalLost(100, 0)] testFullRemovalPreservesOldIntervalAndReopeningUsesFreshSalt()' mutant.log
printf 'Baseline and mutation build exited 0. Mutated test exited %d.\n' "$status"
