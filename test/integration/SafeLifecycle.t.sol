// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeLifecycleFixture, AgreementVault, IPoolManager} from "../fixtures/SafeLifecycleFixture.sol";
import {CoreSeedHarness} from "../fixtures/CoreSeedHarness.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

contract SafeLifecycleTest is SafeLifecycleFixture {
    /// @notice Revisions clear consent, and rights and custody begin only after fresh approvals and execution.
    function testRevisedConsentAndDelayedActivation() public {
        acceptBoth();
        bytes32 old = terms;
        safeCall(address(vault), abi.encodeCall(vault.revise, (draft)), 0, 2);
        terms = vault.termsHash();
        require(
            old != terms && vault.revision() == 3 && vault.treasuryAcceptedRevision() == 0
                && vault.managerAcceptedRevision() == 0
        );
        rejectedVaultCall(abi.encodeCall(vault.accept, (old)));
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, old, terms));
        vault.accept(old);
        vm.prank(executor);
        vm.expectRevert(AgreementVault.NotParty.selector);
        vault.accept(terms);
        rejectedVaultCall(abi.encodeCall(vault.fund, (terms)));
        rejectedVaultCall(abi.encodeCall(vault.activate, (terms)));
        acceptBoth();
        safeCall(address(a), abi.encodeCall(a.approve, (address(vault), PRINCIPAL)), 0, 1);
        rejectedVaultCall(abi.encodeCall(vault.fund, (terms)));
        require(
            a.balanceOf(address(safe)) == PRINCIPAL && b.balanceOf(address(safe)) == PRINCIPAL + BUDGET
                && b.balanceOf(address(escrow)) == 0
        );
        fundAccepted();
        vm.warp(block.timestamp + 61);
        require(vault.start() == 0 && escrow.earned() == 0 && hook.projectedSeconds() == 0);
        rejectedVaultCall(abi.encodeCall(vault.activate, (terms)));
        refreshReference();
        activateFunded();
    }

    /// @notice Even a signed activation with a fresh observation expires at the accepted cutoff.
    function testDelayedSignaturesAtCutoffAllowFundedCancellation() public {
        acceptBoth();
        fundAccepted();
        Request memory activation = requestCall(address(vault), abi.encodeCall(vault.activate, (terms)));
        bytes memory first = signature(owners[0], digest(activation));
        vm.warp(vault.activationCutoff());
        refreshReference();
        bytes memory second = signature(owners[1], digest(activation));
        bytes memory signatures =
            owners[0].addr < owners[1].addr ? bytes.concat(first, second) : bytes.concat(second, first);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GS013"));
        execute(activation, signatures);
        require(
            safe.nonce() == activation.nonce && hook.projectedSeconds() == 0 && vault.start() == 0
                && escrow.earned() == 0
        );
        safeCall(address(vault), abi.encodeCall(vault.cancel, ()), 0, 1);
        require(escrow.refundable() == BUDGET && escrow.reserved() == 0);
        safeCall(address(vault), abi.encodeCall(vault.withdrawIdle, ()), 1, 2);
        require(a.balanceOf(address(safe)) == PRINCIPAL && b.balanceOf(address(safe)) == PRINCIPAL);
        safeCall(address(escrow), abi.encodeCall(escrow.refund, ()), 0, 2);
        require(
            b.balanceOf(address(safe)) == PRINCIPAL + BUDGET && b.balanceOf(address(escrow)) == 0
                && b.balanceOf(manager) == 0
        );
    }

    /// @notice Compare split and unsplit elapsed time, then close with the same floored cumulative entitlement.
    function testSplitCheckpointsAndNormalEarlyClose() public {
        openPeriod();
        uint256 start = vault.start();
        uint256 snapshot = vm.snapshotState();
        vm.warp(start + 101);
        require(hook.checkpoint() == 101);
        uint256 unsplit = escrow.earned();
        require(vm.revertToStateAndDelete(snapshot));
        vm.warp(start + 1);
        hook.checkpoint();
        vm.warp(start + 17);
        hook.checkpoint();
        Request memory stop = requestCall(address(vault), abi.encodeCall(vault.terminate, ()));
        bytes memory signatures = signedPair(digest(stop), owners[0], owners[1]);
        vm.warp(start + 47);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory order = bounds();
        vm.prank(manager);
        vault.add(id, -120, 120, SEED, order);
        require(coreLiquidity() == 2 * SEED && hook.qualifyingSeconds() == 47 && hook.projectedSeconds() == 47);
        vm.warp(start + 101);
        submitSigned(stop, signatures);
        require(hook.qualifyingSeconds() == 101 && escrow.earned() == unsplit && unsplit == 33_666_666);
        recoverPrincipal();
        vm.prank(manager);
        require(escrow.claim() == unsplit);
        uint256 prior = b.balanceOf(address(safe));
        safeCall(address(escrow), abi.encodeCall(escrow.refund, ()), 0, 2);
        require(b.balanceOf(manager) == unsplit && b.balanceOf(address(safe)) == prior + 66_333_334);
        require(b.balanceOf(address(escrow)) == 0 && escrow.reserved() == 0 && escrow.refundable() == 0);
    }

    /// @notice Prepare a bounded order at current chain time for the single active position.
    function bounds() private view returns (AgreementVault.Bounds memory) {
        return AgreementVault.Bounds(terms, block.timestamp, block.timestamp, -240, 240, PRINCIPAL, PRINCIPAL, 0, 0);
    }

    /// @notice A named manager can no longer change the retained position after either close boundary.
    function assertManagerStopped() private {
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory order = bounds();
        vm.prank(manager);
        vm.expectRevert(AgreementVault.InvalidPeriod.selector);
        vault.remove(id, 1, order);
    }

    /// @notice Count 90 + 90 eligible seconds around a 120-second real-core interruption and settle delayed expiry.
    function testManagerServiceAndDelayedExpiry() public {
        openPeriod();
        uint256 start = vault.start();
        vm.warp(start + 30);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory order = bounds();
        address[4] memory denied = [owners[0].addr, owners[1].addr, owners[2].addr, executor];
        for (uint256 i; i < denied.length; ++i) {
            vm.prank(denied[i]);
            vm.expectRevert(AgreementVault.NotManager.selector);
            vault.add(id, -120, 120, SEED, order);
        }
        vm.prank(manager);
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vault.terminate();
        vm.prank(manager);
        vm.expectRevert(AgreementVault.PositionMismatch.selector);
        vault.add(bytes32(uint256(1)), -120, 120, SEED, order);
        require(coreLiquidity() == SEED && vault.positionId() == id && hook.projectedSeconds() == 30);
        vm.prank(manager);
        vault.add(id, -120, 120, SEED, order);
        require(coreLiquidity() == 2 * SEED && hook.projectedSeconds() == 30);
        vm.warp(start + 60);
        order = bounds();
        vm.prank(manager);
        vault.remove(id, SEED, order);
        require(coreLiquidity() == SEED && hook.projectedSeconds() == 60);
        CoreSeedHarness trader = new CoreSeedHarness(IPoolManager(draft.poolManager), key);
        b.mint(address(trader), 10 * PRINCIPAL);
        a.mint(address(trader), 10 * PRINCIPAL);
        vm.warp(start + 90);
        trader.swapUpTo(TickMath.getSqrtPriceAtTick(120));
        (bool qualified,) = hook.qualification();
        require(!qualified && hook.projectedSeconds() == 90);
        vm.warp(start + 210);
        trader.swapDownTo(TickMath.getSqrtPriceAtTick(0));
        (qualified,) = hook.qualification();
        require(qualified && hook.projectedSeconds() == 90);
        vm.warp(start + 300);
        assertManagerStopped();
        require(hook.projectedSeconds() == 180 && escrow.earned() == 60_000_000);
        vm.warp(start + 380);
        vault.finalizeExpiry();
        require(vault.effectiveStop() == start + 300 && hook.qualifyingSeconds() == 180);
        recoverPrincipal();
        vm.prank(manager);
        escrow.claim();
        uint256 prior = b.balanceOf(address(safe));
        safeCall(address(escrow), abi.encodeCall(escrow.refund, ()), 0, 1);
        require(b.balanceOf(address(safe)) == prior + 40_000_000 && b.balanceOf(manager) == 60_000_000);
        require(escrow.refunded() == 40_000_000 && escrow.claimed() == 60_000_000 && b.balanceOf(address(escrow)) == 0);
        require(escrow.claimable() == 0 && escrow.refundable() == 0 && escrow.reserved() == 0);
    }
}
