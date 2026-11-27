// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {CompensationEscrow} from "../../src/CompensationEscrow.sol";
import {CustodyLock, ExactToken} from "../../src/ExactToken.sol";
import {ServiceHook} from "../../src/ServiceHook.sol";
import {ActiveFixture} from "../fixtures/ActiveFixture.sol";
import {CustodyToken} from "../fixtures/CustodyFixture.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

interface VmCode {
    /// @notice Install fixture runtime code at the requested test address.
    function etch(address target, bytes calldata code) external;
}

contract ClockLookalike {
    address public immutable vault;
    address public immutable poolManager;
    PoolId public immutable poolId;
    bytes32 public constant pendingAdd = 0;

    /// @notice Mimic the genuine clock's bindings while exposing synthetic service time.
    constructor(address owner, address core, PoolId id) {
        vault = owner;
        poolManager = core;
        poolId = id;
    }

    /// @notice Expose the synthetic clock value used to challenge settlement authentication.
    function projectedSeconds() external pure returns (uint256) {
        return 300;
    }
}

contract CompensationSettlementTest is ActiveFixture {
    uint256 private constant UNIT = 1_000_000;
    bool private duringRemoval;
    error ReserveStolen(uint256 expectedBalance, uint256 actualBalance);

    /// @notice Let a third party trigger the manager's fixed payout and return the base units paid.
    function claimPayment() private returns (uint256) {
        vm.prank(DONOR);
        return escrow.claim();
    }

    /// @notice Pull the final treasury remainder under the fixture's terminal settlement conditions.
    function refundBudget() private returns (uint256) {
        vm.prank(DONOR);
        return escrow.refund();
    }

    /// @notice Reconcile projected rights and actual escrow custody, including unsolicited gifts.
    function assertPaymentLedger(uint256 earned, uint256 claimed, uint256 refunded, uint256 refundable, uint256 gifts)
        private
        view
    {
        require(escrow.fundedBudget() == BUDGET && escrow.earned() == earned, "funding and entitlement");
        require(escrow.claimed() == claimed && escrow.refunded() == refunded, "settled counters");
        require(escrow.reserved() == earned - claimed && escrow.claimable() == earned - claimed, "unpaid reserve");
        require(escrow.refundable() == refundable, "refund due");
        uint256 remaining = BUDGET - claimed - refunded;
        require(escrow.accounted() == remaining && b.balanceOf(address(escrow)) == remaining + gifts, "custody");
        require(b.balanceOf(MANAGER) == claimed && b.balanceOf(DONOR) == 0, "fixed manager and caller");
    }

    /// @notice Substitute a lookalike clock before activation and check that it cannot create manager entitlement.
    function testLookalikeClockCannotCreateSettlementRights() public {
        prepareFundedFixture();
        ClockLookalike mimic = new ClockLookalike(address(vault), address(core), key.toId());
        VmCode(address(vm)).etch(address(hook), address(mimic).code);
        require(hook.vault() == address(vault) && hook.poolManager() == core && hook.projectedSeconds() == 300);
        vm.expectRevert(AgreementVault.InvalidServiceHook.selector);
        vault.activate(h);
        (ServiceHook clock, uint256 duration, bool terminal) = vault.settlementContext();
        require(address(clock) == address(0) && duration == 0 && !terminal);
        vm.expectRevert(CompensationEscrow.ClaimUnavailable.selector);
        escrow.claim();
        assertPaymentLedger(0, 0, 0, 0, 0);
        vault.cancel();
        require(claimPayment() == 0 && refundBudget() == BUDGET && b.balanceOf(address(this)) == BUDGET);
    }

    /// @notice Run through full service and delayed claims and verify exactly one budget reaches the manager.
    function testFullServiceAndLateClaimPayOnce() public {
        activateFixture();
        vm.warp(10_350);
        require(vault.recordedStop() == 0 && hook.qualifyingSeconds() == 0);
        assertPaymentLedger(BUDGET, 0, 0, 0, 0);
        require(claimPayment() == BUDGET && hook.qualifyingSeconds() == 300);
        require(refundBudget() == 0 && claimPayment() == 0 && vault.recordedStop() == 0);
        assertPaymentLedger(BUDGET, BUDGET, 0, 0, 0);
    }

    /// @notice Interrupt service and gift escrow tokens, then reconcile both possible terminal pull orders.
    function testInterruptedServiceBothPullOrdersAndGiftsAtExactExpiry() public {
        activateFixture();
        giveTokens(b, address(escrow), 17);
        vm.warp(10_090);
        swapToTick(120);
        vm.warp(10_210);
        swapToTick(0);
        vm.warp(10_299);
        require(escrow.refundable() == 0);
        vm.expectRevert(CompensationEscrow.NotTerminal.selector);
        escrow.refund();
        vm.warp(10_300);
        assertPaymentLedger(60 * UNIT, 0, 0, 40 * UNIT, 17);
        uint256 snapshot = vm.snapshotState();
        require(claimPayment() == 60 * UNIT && refundBudget() == 40 * UNIT);
        assertPaymentLedger(60 * UNIT, 60 * UNIT, 40 * UNIT, 0, 17);
        require(b.balanceOf(address(this)) == 40 * UNIT);
        require(vm.revertToStateAndDelete(snapshot));
        require(refundBudget() == 40 * UNIT && hook.qualifyingSeconds() == 180 && vault.recordedStop() == 0);
        assertPaymentLedger(60 * UNIT, 0, 40 * UNIT, 0, 17);
        require(claimPayment() == 60 * UNIT && claimPayment() == 0 && refundBudget() == 0);
        assertPaymentLedger(60 * UNIT, 60 * UNIT, 40 * UNIT, 0, 17);
        require(b.balanceOf(address(this)) == 40 * UNIT);
    }

    /// @notice Compare split checkpoints and small claims with the original cumulative floor at three seconds.
    function testOneThenThreeSecondsAndPartitionIndependentEntitlement() public {
        activateFixture();
        uint256 snapshot = vm.snapshotState();
        vm.warp(10_003);
        uint256 single = claimPayment();
        require(single == UNIT && vm.revertToStateAndDelete(snapshot));
        vm.warp(10_001);
        assertPaymentLedger(333_333, 0, 0, 0, 0);
        require(hook.qualifyingSeconds() == 0 && claimPayment() == 333_333 && hook.qualifyingSeconds() == 1);
        vm.warp(10_002);
        require(hook.checkpoint() == 2 && hook.checkpoint() == 2);
        vm.warp(10_003);
        require(claimPayment() == 666_667 && claimPayment() == 0);
        assertPaymentLedger(single, single, 0, 0, 0);
    }

    /// @notice Block the manager payout during a fee-bearing close and reconcile independent principal recovery.
    function testManagerPaymentFailureCloseoutWithFeeBearingPrincipal() public {
        activateFixture();
        swapToTick(-20);
        vm.warp(10_120);
        require(claimPayment() == 40 * UNIT);
        vm.warp(10_180);
        b.setFault(address(escrow), MANAGER, CustodyToken.Fault.Revert);
        faults.mockCallRevert(address(adapter), "", hex"bad0");
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        escrow.claim();
        require(hook.qualifyingSeconds() == 120 && hook.projectedSeconds() == 180, "failed pull checkpoint rollback");
        assertPaymentLedger(60 * UNIT, 40 * UNIT, 0, 0, 0);
        vault.terminate();
        require(vault.recordedStop() == 10_180 && hook.qualifyingSeconds() == 180);
        assertPaymentLedger(60 * UNIT, 40 * UNIT, 0, 40 * UNIT, 0);
        vault.exitLiquidity();
        vault.withdrawIdle();
        // Real swap at -20. Removal returns 698,218,788 A principal plus 301,038 A fees,
        // and 498,228,754 B principal. Both idle balances started at PRINCIPAL - COST.
        assertCustodyBalances(2_100_346_049, 1_900_054_977, 0, 0, 60 * UNIT);
        require(vault.positionId() == 0 && seedRangeLiquidity(address(vault), bytes32(uint256(1))) == 0);
        require(refundBudget() == 40 * UNIT && b.balanceOf(address(this)) == 1_940_054_977);
        assertPaymentLedger(60 * UNIT, 40 * UNIT, 40 * UNIT, 0, 0);
        b.setFault(address(escrow), MANAGER, CustodyToken.Fault.None);
        require(claimPayment() == 20 * UNIT && refundBudget() == 0 && claimPayment() == 0);
        assertPaymentLedger(60 * UNIT, 60 * UNIT, 40 * UNIT, 0, 0);
    }

    /// @notice Refund after partial payment and require the escrow to retain every unpaid earned base unit.
    function testTerminalRefundLeavesUnpaidEarnedReserve() public {
        activateFixture();
        vm.warp(10_120);
        require(claimPayment() == 40 * UNIT);
        vm.warp(10_180);
        vault.terminate();
        uint256 beforeTreasury = b.balanceOf(address(this));
        uint256 refund = refundBudget();
        uint256 remaining = b.balanceOf(address(escrow));
        if (remaining != 20 * UNIT) revert ReserveStolen(20 * UNIT, remaining);
        require(refund == 40 * UNIT && b.balanceOf(address(this)) - beforeTreasury == refund);
        require(claimPayment() == remaining);
        assertPaymentLedger(60 * UNIT, 60 * UNIT, 40 * UNIT, 0, 0);
    }

    /// @notice Block the treasury refund route and verify principal withdrawal and manager payment remain available.
    function testRefundFailurePreservesIndependentPrincipalAndManagerReceipt() public {
        activateFixture();
        vm.warp(10_120);
        vault.terminate();
        b.setFault(address(escrow), address(this), CustodyToken.Fault.FalseReturn);
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        escrow.refund();
        assertPaymentLedger(40 * UNIT, 0, 0, 60 * UNIT, 0);
        vault.withdrawIdle();
        vault.exitLiquidity();
        vault.withdrawIdle();
        assertCustodyBalances(PRINCIPAL - 1, PRINCIPAL - 1, 0, 0, BUDGET);
        require(claimPayment() == 40 * UNIT);
        assertPaymentLedger(40 * UNIT, 40 * UNIT, 0, 60 * UNIT, 0);
        b.setFault(address(escrow), address(this), CustodyToken.Fault.None);
        require(refundBudget() == 60 * UNIT && b.balanceOf(address(this)) == PRINCIPAL - 1 + 60 * UNIT);
        assertPaymentLedger(40 * UNIT, 40 * UNIT, 60 * UNIT, 0, 0);
    }

    /// @notice Apply a payout fault and check the specified error and unchanged rights.
    function expectClaimRollback(CustodyToken.Fault fault, bytes memory reason) private {
        b.setFault(address(escrow), MANAGER, fault);
        vm.expectRevert(reason);
        escrow.claim();
        assertPaymentLedger(UNIT, 0, 0, 0, 0);
        require(hook.qualifyingSeconds() == 0);
    }

    /// @notice Inject false, malformed and inexact payouts and require balances and claim rights to roll back.
    function testFalseMalformedAndInexactClaimsRollback() public {
        activateFixture();
        vm.warp(10_003);
        bytes memory failed = abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b));
        expectClaimRollback(CustodyToken.Fault.FalseReturn, failed);
        expectClaimRollback(CustodyToken.Fault.InvalidReturn, failed);
        expectClaimRollback(
            CustodyToken.Fault.ShortReceipt,
            abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), MANAGER)
        );
        expectClaimRollback(
            CustodyToken.Fault.ExtraDebit,
            abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(escrow))
        );
        b.setFault(address(escrow), MANAGER, CustodyToken.Fault.NoReturn);
        require(claimPayment() == UNIT);
    }

    /// @notice Run the test's configured probe during a mock token transfer.
    function onTransfer() public override {
        require(msg.sender == address(b));
        if (duringRemoval) {
            duringRemoval = false;
            require(
                seedRangeLiquidity(address(vault), bytes32(uint256(1))) == SEED / 2 && hook.observedLiquidity() == SEED
            );
            vm.expectRevert(CompensationEscrow.NotTerminal.selector);
            escrow.refund();
            require(escrow.claim() == 10 * UNIT && hook.observedLiquidity() == SEED);
        } else {
            vm.expectRevert(CustodyLock.ReentrantCall.selector);
            escrow.claim();
            vm.expectRevert(CustodyLock.ReentrantCall.selector);
            escrow.refund();
            ++blockedCalls;
        }
    }

    /// @notice Probe settlement during removal and both payouts and compare balances after reentrant calls.
    function testSettlementDuringVaultRemovalAndReentryOnBothPayouts() public {
        activateFixture();
        vm.warp(10_030);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        duringRemoval = true;
        b.setProbe(this);
        vm.prank(MANAGER);
        vault.remove(id, SEED / 2, bounds);
        require(!duringRemoval && blockedCalls == 1 && hook.observedLiquidity() == SEED / 2);
        vm.warp(10_060);
        vault.terminate();
        require(claimPayment() == 0 && refundBudget() == 90 * UNIT && blockedCalls == 2);
        assertPaymentLedger(10 * UNIT, 10 * UNIT, 90 * UNIT, 0, 0);
    }
}
