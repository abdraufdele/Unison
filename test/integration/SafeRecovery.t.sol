// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeLifecycleFixture, AgreementVault, Vm, CustodyToken} from "../fixtures/SafeLifecycleFixture.sol";
import {ExactToken} from "../../src/ExactToken.sol";

contract SafeRecoveryTest is SafeLifecycleFixture {
    /// @notice A signed stop is inert until inclusion. A blocked earned payment leaves independent principal and refund routes.
    function testPendingStopAndBlockedManagerPayment() public {
        openPeriod();
        uint256 start = vault.start();
        vm.warp(start + 1);
        require(hook.checkpoint() == 1 && escrow.earned() == 333_333);
        vm.warp(start + 120);
        require(hook.checkpoint() == 120 && hook.checkpoint() == 120 && escrow.earned() == 40_000_000);
        vm.prank(manager);
        require(escrow.claim() == 40_000_000);
        Request memory stop = requestCall(address(vault), abi.encodeCall(vault.terminate, ()));
        bytes memory signatures = signedPair(digest(stop), owners[0], owners[1]);
        vm.warp(start + 180);
        require(
            safe.nonce() == stop.nonce && vault.state() == AgreementVault.State.Active && vault.effectiveStop() == 0
        );
        require(hook.projectedSeconds() == 180 && escrow.earned() == 60_000_000 && escrow.reserved() == 20_000_000);
        b.setFault(address(escrow), manager, CustodyToken.Fault.Revert);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        escrow.claim();
        require(
            escrow.claimed() == 40_000_000 && b.balanceOf(manager) == 40_000_000
                && b.balanceOf(address(escrow)) == 60_000_000
        );
        submitSigned(stop, signatures);
        require(
            vault.effectiveStop() == start + 180 && hook.qualifyingSeconds() == 180 && escrow.refundable() == 40_000_000
        );
        vm.warp(start + 400);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory order =
            AgreementVault.Bounds(terms, block.timestamp, block.timestamp, -240, 240, PRINCIPAL, PRINCIPAL, 0, 0);
        vm.prank(manager);
        vm.expectRevert(AgreementVault.InvalidPeriod.selector);
        vault.remove(id, 1, order);
        Request memory exit = requestCall(address(vault), abi.encodeCall(vault.exitLiquidity, ()));
        bytes memory single = signature(owners[0], digest(exit));
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GS020"));
        execute(exit, single);
        require(safe.nonce() == exit.nonce && coreLiquidity() == SEED && b.balanceOf(address(safe)) == 0);
        (uint256 recoveredA, uint256 recoveredB) = recoverPrincipal();
        require(recoveredA == PRINCIPAL - 1 && recoveredB == PRINCIPAL - 1, "parity rounding");
        safeCall(address(escrow), abi.encodeCall(escrow.refund, ()), 0, 1);
        require(
            b.balanceOf(address(safe)) == recoveredB + 40_000_000 && escrow.refunded() == 40_000_000
                && escrow.refundable() == 0
        );
        require(
            b.balanceOf(address(escrow)) == 20_000_000 && escrow.reserved() == 20_000_000
                && escrow.claimable() == 20_000_000
        );
        b.setFault(address(escrow), manager, CustodyToken.Fault.None);
        vm.prank(manager);
        require(escrow.claim() == 20_000_000);
        require(b.balanceOf(manager) == 60_000_000 && escrow.claimed() == 60_000_000 && escrow.reserved() == 0);
        vm.prank(manager);
        require(escrow.claim() == 0);
        safeCall(address(escrow), abi.encodeCall(escrow.refund, ()), 0, 2);
        safeCall(address(vault), abi.encodeCall(vault.exitLiquidity, ()), 0, 2);
        safeCall(address(vault), abi.encodeCall(vault.withdrawIdle, ()), 1, 2);
        require(a.balanceOf(address(safe)) == recoveredA && b.balanceOf(address(safe)) == recoveredB + 40_000_000);
        require(
            b.balanceOf(manager) == 60_000_000 && b.balanceOf(address(escrow)) == 0 && escrow.claimable() == 0
                && escrow.refundable() == 0
        );
    }

    /// @notice A failed refund can either revert the outer call or consume the Safe nonce with an explicit failure log.
    function testBlockedRefundAllowsExitAndFreshNonceRetry() public {
        openPeriod();
        vm.warp(vault.start() + 90);
        safeCall(address(vault), abi.encodeCall(vault.terminate, ()), 0, 1);
        b.setFault(address(escrow), address(safe), CustodyToken.Fault.Revert);
        Request memory refund = requestCall(address(escrow), abi.encodeCall(escrow.refund, ()));
        bytes memory signatures = signedPair(digest(refund), owners[0], owners[1]);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GS013"));
        execute(refund, signatures);
        require(safe.nonce() == refund.nonce);
        uint256 safeTxGas = 1_000_000;
        bytes32 hash = digestWithGas(refund, safeTxGas);
        signatures = signedPair(hash, owners[0], owners[2]);
        vm.recordLogs();
        require(!executeWithGas(refund, signatures, safeTxGas), "inner refund unexpectedly succeeded");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory failed = eventFrom(logs, address(safe), keccak256("ExecutionFailure(bytes32,uint256)"));
        require(failed.topics.length == 2 && failed.topics[1] == hash && abi.decode(failed.data, (uint256)) == 0);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(safe)) require(logs[i].topics[0] != SUCCESS);
        }
        require(
            safe.nonce() == refund.nonce + 1 && vault.state() == AgreementVault.State.Terminated
                && coreLiquidity() == SEED
        );
        require(
            escrow.refunded() == 0 && escrow.claimed() == 0 && escrow.refundable() == 70_000_000
                && escrow.reserved() == 30_000_000
        );
        require(b.balanceOf(address(escrow)) == BUDGET && b.balanceOf(address(safe)) == 0 && b.balanceOf(manager) == 0);
        (, uint256 receivedB) = recoverPrincipal();
        require(receivedB == PRINCIPAL - 1 && escrow.reserved() == 30_000_000 && escrow.refundable() == 70_000_000);
        b.setFault(address(escrow), address(safe), CustodyToken.Fault.None);
        safeCall(address(escrow), refund.data, 1, 2);
        require(b.balanceOf(address(safe)) == receivedB + 70_000_000 && b.balanceOf(address(escrow)) == 30_000_000);
        vm.prank(manager);
        require(escrow.claim() == 30_000_000);
        require(
            escrow.refunded() == 70_000_000 && b.balanceOf(manager) == 30_000_000 && b.balanceOf(address(escrow)) == 0
        );
        require(escrow.claimable() == 0 && escrow.refundable() == 0);
    }
}
