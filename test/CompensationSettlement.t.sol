// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../src/AgreementVault.sol";
import {CompensationEscrow} from "../src/CompensationEscrow.sol";
import {CustodyLock, ExactToken} from "../src/ExactToken.sol";
import {ServiceHook} from "../src/ServiceHook.sol";
import {ActiveFixture} from "./fixtures/ActiveFixture.sol";
import {CustodyToken} from "./fixtures/CustodyFixture.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

interface VmCode {
    function etch(address target, bytes calldata code) external;
}

contract ClockLookalike {
    address public immutable vault;
    address public immutable poolManager;
    PoolId public immutable poolId;
    bytes32 public constant pendingAdd = 0;

    constructor(address owner, address core, PoolId id) {
        vault = owner;
        poolManager = core;
        poolId = id;
    }

    function projectedSeconds() external pure returns (uint256) {
        return 300;
    }
}

contract CompensationSettlementTest is ActiveFixture {
    uint256 private constant UNIT = 1_000_000;
    bool private duringRemoval;
    error ReserveStolen(uint256 expectedBalance, uint256 actualBalance);

    function _claim() private returns (uint256) {
        vm.prank(DONOR);
        return escrow.claim();
    }

    function _refund() private returns (uint256) {
        vm.prank(DONOR);
        return escrow.refund();
    }

    function _ledger(uint256 earned, uint256 claimed, uint256 refunded, uint256 refundable, uint256 gifts)
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

    function testLookalikeClockCannotCreateSettlementRights() public {
        _ready();
        ClockLookalike mimic = new ClockLookalike(address(vault), address(core), key.toId());
        VmCode(address(vm)).etch(address(hook), address(mimic).code);
        require(hook.vault() == address(vault) && hook.poolManager() == core && hook.projectedSeconds() == 300);
        vm.expectRevert(AgreementVault.InvalidServiceHook.selector);
        vault.activate(h);
        (ServiceHook clock, uint256 duration, bool terminal) = vault.settlementContext();
        require(address(clock) == address(0) && duration == 0 && !terminal);
        vm.expectRevert(CompensationEscrow.ClaimUnavailable.selector);
        escrow.claim();
        _ledger(0, 0, 0, 0, 0);
        vault.cancel();
        require(_claim() == 0 && _refund() == BUDGET && b.balanceOf(address(this)) == BUDGET);
    }

    function testFullServiceAndLateClaimPayOnce() public {
        _active();
        vm.warp(10_350);
        require(vault.recordedStop() == 0 && hook.qualifyingSeconds() == 0);
        _ledger(BUDGET, 0, 0, 0, 0);
        require(_claim() == BUDGET && hook.qualifyingSeconds() == 300);
        require(_refund() == 0 && _claim() == 0 && vault.recordedStop() == 0);
        _ledger(BUDGET, BUDGET, 0, 0, 0);
    }

    function testInterruptedServiceBothPullOrdersAndGiftsAtExactExpiry() public {
        _active();
        _give(b, address(escrow), 17);
        vm.warp(10_090);
        _swap(120);
        vm.warp(10_210);
        _swap(0);
        vm.warp(10_299);
        require(escrow.refundable() == 0);
        vm.expectRevert(CompensationEscrow.NotTerminal.selector);
        escrow.refund();
        vm.warp(10_300);
        _ledger(60 * UNIT, 0, 0, 40 * UNIT, 17);
        uint256 snapshot = vm.snapshotState();
        require(_claim() == 60 * UNIT && _refund() == 40 * UNIT);
        _ledger(60 * UNIT, 60 * UNIT, 40 * UNIT, 0, 17);
        require(b.balanceOf(address(this)) == 40 * UNIT);
        require(vm.revertToStateAndDelete(snapshot));
        require(_refund() == 40 * UNIT && hook.qualifyingSeconds() == 180 && vault.recordedStop() == 0);
        _ledger(60 * UNIT, 0, 40 * UNIT, 0, 17);
        require(_claim() == 60 * UNIT && _claim() == 0 && _refund() == 0);
        _ledger(60 * UNIT, 60 * UNIT, 40 * UNIT, 0, 17);
        require(b.balanceOf(address(this)) == 40 * UNIT);
    }

    function testOneThenThreeSecondsAndPartitionIndependentEntitlement() public {
        _active();
        uint256 snapshot = vm.snapshotState();
        vm.warp(10_003);
        uint256 single = _claim();
        require(single == UNIT && vm.revertToStateAndDelete(snapshot));
        vm.warp(10_001);
        _ledger(333_333, 0, 0, 0, 0);
        require(hook.qualifyingSeconds() == 0 && _claim() == 333_333 && hook.qualifyingSeconds() == 1);
        vm.warp(10_002);
        require(hook.checkpoint() == 2 && hook.checkpoint() == 2);
        vm.warp(10_003);
        require(_claim() == 666_667 && _claim() == 0);
        _ledger(single, single, 0, 0, 0);
    }

    function testManagerPaymentFailureCloseoutWithFeeBearingPrincipal() public {
        _active();
        _swap(-20);
        vm.warp(10_120);
        require(_claim() == 40 * UNIT);
        vm.warp(10_180);
        b.setFault(address(escrow), MANAGER, CustodyToken.Fault.Revert);
        faults.mockCallRevert(address(adapter), "", hex"bad0");
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        escrow.claim();
        require(hook.qualifyingSeconds() == 120 && hook.projectedSeconds() == 180, "failed pull checkpoint rollback");
        _ledger(60 * UNIT, 40 * UNIT, 0, 0, 0);
        vault.terminate();
        require(vault.recordedStop() == 10_180 && hook.qualifyingSeconds() == 180);
        _ledger(60 * UNIT, 40 * UNIT, 0, 40 * UNIT, 0);
        vault.exitLiquidity();
        vault.withdrawIdle();
        // Real swap at -20. Removal returns 698,218,788 A principal plus 301,038 A fees,
        // and 498,228,754 B principal. Both idle balances started at PRINCIPAL - COST.
        _balances(2_100_346_049, 1_900_054_977, 0, 0, 60 * UNIT);
        require(vault.positionId() == 0 && _liquidity(address(vault), bytes32(uint256(1))) == 0);
        require(_refund() == 40 * UNIT && b.balanceOf(address(this)) == 1_940_054_977);
        _ledger(60 * UNIT, 40 * UNIT, 40 * UNIT, 0, 0);
        b.setFault(address(escrow), MANAGER, CustodyToken.Fault.None);
        require(_claim() == 20 * UNIT && _refund() == 0 && _claim() == 0);
        _ledger(60 * UNIT, 60 * UNIT, 40 * UNIT, 0, 0);
    }

    function testTerminalRefundLeavesUnpaidEarnedReserve() public {
        _active();
        vm.warp(10_120);
        require(_claim() == 40 * UNIT);
        vm.warp(10_180);
        vault.terminate();
        uint256 beforeTreasury = b.balanceOf(address(this));
        uint256 refund = _refund();
        uint256 remaining = b.balanceOf(address(escrow));
        if (remaining != 20 * UNIT) revert ReserveStolen(20 * UNIT, remaining);
        require(refund == 40 * UNIT && b.balanceOf(address(this)) - beforeTreasury == refund);
        require(_claim() == remaining);
        _ledger(60 * UNIT, 60 * UNIT, 40 * UNIT, 0, 0);
    }

    function testRefundFailurePreservesIndependentPrincipalAndManagerReceipt() public {
        _active();
        vm.warp(10_120);
        vault.terminate();
        b.setFault(address(escrow), address(this), CustodyToken.Fault.FalseReturn);
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        escrow.refund();
        _ledger(40 * UNIT, 0, 0, 60 * UNIT, 0);
        vault.withdrawIdle();
        vault.exitLiquidity();
        vault.withdrawIdle();
        _balances(PRINCIPAL - 1, PRINCIPAL - 1, 0, 0, BUDGET);
        require(_claim() == 40 * UNIT);
        _ledger(40 * UNIT, 40 * UNIT, 0, 60 * UNIT, 0);
        b.setFault(address(escrow), address(this), CustodyToken.Fault.None);
        require(_refund() == 60 * UNIT && b.balanceOf(address(this)) == PRINCIPAL - 1 + 60 * UNIT);
        _ledger(40 * UNIT, 40 * UNIT, 60 * UNIT, 0, 0);
    }

    function _badClaim(CustodyToken.Fault fault, bytes memory reason) private {
        b.setFault(address(escrow), MANAGER, fault);
        vm.expectRevert(reason);
        escrow.claim();
        _ledger(UNIT, 0, 0, 0, 0);
        require(hook.qualifyingSeconds() == 0);
    }

    function testFalseMalformedAndInexactClaimsRollback() public {
        _active();
        vm.warp(10_003);
        bytes memory failed = abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b));
        _badClaim(CustodyToken.Fault.FalseReturn, failed);
        _badClaim(CustodyToken.Fault.InvalidReturn, failed);
        _badClaim(
            CustodyToken.Fault.ShortReceipt,
            abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), MANAGER)
        );
        _badClaim(
            CustodyToken.Fault.ExtraDebit,
            abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(escrow))
        );
        b.setFault(address(escrow), MANAGER, CustodyToken.Fault.NoReturn);
        require(_claim() == UNIT);
    }

    function onTransfer() public override {
        require(msg.sender == address(b));
        if (duringRemoval) {
            duringRemoval = false;
            require(_liquidity(address(vault), bytes32(uint256(1))) == SEED / 2 && hook.observedLiquidity() == SEED);
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

    function testSettlementDuringVaultRemovalAndReentryOnBothPayouts() public {
        _active();
        vm.warp(10_030);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        duringRemoval = true;
        b.setProbe(this);
        vm.prank(MANAGER);
        vault.remove(id, SEED / 2, bounds);
        require(!duringRemoval && blockedCalls == 1 && hook.observedLiquidity() == SEED / 2);
        vm.warp(10_060);
        vault.terminate();
        require(_claim() == 0 && _refund() == 90 * UNIT && blockedCalls == 2);
        _ledger(10 * UNIT, 10 * UNIT, 90 * UNIT, 0, 0);
    }
}
