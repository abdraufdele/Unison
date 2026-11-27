// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {CompensationEscrow} from "../../src/CompensationEscrow.sol";
import {ExactToken} from "../../src/ExactToken.sol";
import {CustodyFixture, CustodyToken} from "../fixtures/CustodyFixture.sol";
import {Vm} from "../helpers/Vm.sol";

contract AgreementVaultCancellationTest is CustodyFixture {
    /// @notice Cancel a partially accepted draft with gifts and verify each asset's recovery path.
    function testTreasuryCancelsDraftWithGiftsAndOneAcceptance() public {
        vault.accept(vault.termsHash());
        giveTokens(b, address(escrow), BUDGET);
        giveTokens(a, address(vault), 41);
        giveTokens(b, address(vault), 53);
        vault.cancel();
        require(vault.state() == AgreementVault.State.Cancelled, "cancelled");
        assertCustodyBalances(PRINCIPAL, PRINCIPAL + BUDGET, 41, 53, BUDGET);
        require(escrow.fundedBudget() == 0 && escrow.refundable() == 0 && escrow.refund() == 0, "unfunded rights");
        (uint256 amount0, uint256 amount1) = vault.withdrawIdle();
        require(amount0 == 41 && amount1 == 53, "pair gifts");
        assertCustodyBalances(PRINCIPAL + 41, PRINCIPAL + BUDGET + 53, 0, 0, BUDGET);
    }

    /// @notice Cancel after both acceptances and require edits, new consent and funding to stay closed.
    function testTreasuryCancelsAcceptedAndClosesAllConsentAndFunding() public {
        acceptTerms();
        bytes32 h = vault.termsHash();
        AgreementVault.Bindings memory bindings = vault.currentTerms().bindings;
        vault.cancel();
        vm.expectRevert(AgreementVault.TermsClosed.selector);
        vault.fund(h);
        vm.expectRevert(AgreementVault.TermsClosed.selector);
        vault.revise(bindings);
        vm.expectRevert(AgreementVault.TermsClosed.selector);
        vault.accept(h);
        vm.expectRevert(AgreementVault.TermsClosed.selector);
        vm.prank(MANAGER);
        vault.accept(h);
        require(vault.state() == AgreementVault.State.Cancelled && escrow.refund() == 0, "accepted cancellation");
    }

    /// @notice Call cancellation as a stranger exactly at cutoff and verify recovery becomes available.
    function testStrangerCanCancelPreciselyAtCutoff() public {
        fundFixture();
        uint256 cutoff = vault.activationCutoff();
        vm.warp(cutoff - 1);
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(DONOR);
        vault.cancel();
        vm.warp(cutoff);
        vm.prank(DONOR);
        vault.cancel();
        require(vault.state() == AgreementVault.State.Cancelled && escrow.refundable() == BUDGET, "cutoff cancellation");
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    /// @notice Repeat permissionless cancellation after cutoff and verify the terminal state is stable.
    function testStrangerCanCancelAfterCutoffAndRepeat() public {
        vm.warp(vault.activationCutoff() + 1);
        vm.prank(DONOR);
        vault.cancel();
        vm.prank(MANAGER);
        vault.cancel();
        require(vault.state() == AgreementVault.State.Cancelled && escrow.refund() == 0, "late cancellation");
    }

    /// @notice Attempt early recovery and unauthorized withdrawal and require the state and caller guards.
    function testRecoveryRequiresCancellationAndPrincipalRequiresTreasury() public {
        vm.expectRevert(CompensationEscrow.NotTerminal.selector);
        escrow.refund();
        fundFixture();
        vm.expectRevert(CompensationEscrow.NotTerminal.selector);
        escrow.refund();
        vm.expectRevert(AgreementVault.NotCancelled.selector);
        vault.withdrawIdle();
        vault.cancel();
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(MANAGER);
        vault.withdrawIdle();
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    /// @notice Cancel after funding, pull both custodies separately and verify receipts and repeated zero pulls.
    function testFundedCancellationIndependentPullsEventsAndRepeatRecovery() public {
        fundFixture();
        giveTokens(a, address(vault), 8);
        giveTokens(b, address(vault), 12);
        giveTokens(b, address(escrow), 17);
        bytes32 h = vault.termsHash();
        vm.recordLogs();
        vault.cancel();
        vault.cancel();
        assertCustodyBalances(0, 0, PRINCIPAL + 8, PRINCIPAL + 12, BUDGET + 17);
        require(escrow.refundable() == BUDGET && escrow.refunded() == 0, "all credited budget due");
        vm.prank(DONOR);
        require(escrow.refund() == BUDGET, "refund amount");
        assertCustodyBalances(0, BUDGET, PRINCIPAL + 8, PRINCIPAL + 12, 17);
        require(b.balanceOf(DONOR) == 0 && b.balanceOf(MANAGER) == 0, "fixed recipient");
        (uint256 amount0, uint256 amount1) = vault.withdrawIdle();
        require(amount0 == PRINCIPAL + 8 && amount1 == PRINCIPAL + 12, "principal and gifts");
        require(escrow.refund() == 0, "repeat refund");
        (amount0, amount1) = vault.withdrawIdle();
        require(
            amount0 == 0 && amount1 == 0 && escrow.refunded() == BUDGET && escrow.refundable() == 0, "empty recovery"
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 3, "one receipt per effect");
        require(
            logs[0].emitter == address(vault) && logs[0].topics[0] == keccak256("Cancelled(uint256,bytes32,address)")
                && uint256(logs[0].topics[1]) == vault.revision() && logs[0].topics[2] == h
                && address(uint160(uint256(logs[0].topics[3]))) == address(this),
            "cancel receipt"
        );
        require(
            logs[1].emitter == address(escrow) && logs[1].topics[0] == keccak256("BudgetRefunded(address,uint256)")
                && address(uint160(uint256(logs[1].topics[1]))) == address(this)
                && abi.decode(logs[1].data, (uint256)) == BUDGET,
            "refund receipt"
        );
        require(
            logs[2].emitter == address(vault)
                && logs[2].topics[0] == keccak256("IdleWithdrawn(address,uint256,uint256)")
                && address(uint160(uint256(logs[2].topics[1]))) == address(this)
                && keccak256(logs[2].data) == keccak256(abi.encode(PRINCIPAL + 8, PRINCIPAL + 12)),
            "withdrawal receipt"
        );
        assertCustodyBalances(PRINCIPAL + 8, PRINCIPAL + BUDGET + 12, 0, 0, 17);
        giveTokens(b, address(vault), 3);
        vault.withdrawIdle();
        assertCustodyBalances(PRINCIPAL + 8, PRINCIPAL + BUDGET + 15, 0, 0, 17);
    }

    /// @notice Block only the escrow refund route and verify the treasury can still receive its principal.
    function testBlockedEscrowToTreasuryRoutePreservesRefundDuringPrincipalExit() public {
        fundFixture();
        b.setFault(address(escrow), address(this), CustodyToken.Fault.Revert);
        vault.cancel();
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        vm.prank(DONOR);
        escrow.refund();
        require(escrow.refunded() == 0 && escrow.refundable() == BUDGET, "failed refund consumed right");
        vault.withdrawIdle();
        assertCustodyBalances(PRINCIPAL, PRINCIPAL, 0, 0, BUDGET);
        require(escrow.refundable() == BUDGET && vault.state() == AgreementVault.State.Cancelled, "independent exit");
        b.setFault(address(escrow), address(this), CustodyToken.Fault.None);
        vm.prank(MANAGER);
        require(escrow.refund() == BUDGET, "restored refund");
        assertCustodyBalances(PRINCIPAL, PRINCIPAL + BUDGET, 0, 0, 0);
    }

    /// @notice Fail each recovery leg and check that restoring transfer behavior permits the original rights.
    function testShortRefundAndFailedSecondPrincipalLegKeepRecoveryRights() public {
        fundFixture();
        b.setFault(address(escrow), address(this), CustodyToken.Fault.ShortReceipt);
        vault.cancel();
        vm.expectRevert(abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(this)));
        escrow.refund();
        require(escrow.refundable() == BUDGET && escrow.refunded() == 0, "refund rollback");
        b.setFault(address(vault), address(this), CustodyToken.Fault.FalseReturn);
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        vault.withdrawIdle();
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
        require(escrow.refund() == BUDGET, "refund independent of blocked principal");
        b.setFault(address(vault), address(this), CustodyToken.Fault.None);
        vault.withdrawIdle();
        assertCustodyBalances(PRINCIPAL, PRINCIPAL + BUDGET, 0, 0, 0);
    }

    /// @notice Probe reentry during principal withdrawal and refund and verify the fixed-party receipts.
    function testReentryDuringBothRecoveries() public {
        fundFixture();
        vault.cancel();
        b.setProbe(this);
        probe = Probe.Refund;
        require(escrow.refund() == BUDGET && blockedCalls == 1, "refund callback");
        probe = Probe.Withdrawal;
        vault.withdrawIdle();
        require(blockedCalls == 2 && escrow.refundable() == 0, "principal callback");
        assertCustodyBalances(PRINCIPAL, PRINCIPAL + BUDGET, 0, 0, 0);
    }
}
