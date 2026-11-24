// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ActiveFixture} from "./fixtures/ActiveFixture.sol";
import {AgreementVault} from "../src/AgreementVault.sol";
import {ServiceHook} from "../src/ServiceHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CoreSeedHarness} from "./fixtures/CoreSeedHarness.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

contract ServiceClockTest is ActiveFixture {
    using StateLibrary for IPoolManager;

    error OldIntervalLost(uint256 expectedSeconds, uint256 persistedSeconds);

    // Independent interval oracle. Read the vault lifecycle and exact core key at the LEFT
    // endpoint. Advance simulated time and integrate that predicate before the next action.
    uint256 private expected;

    function _actualQualification() private view returns (bool) {
        int24 lower = vault.positionLower();
        int24 upper = vault.positionUpper();
        bytes32 salt = vault.positionSalt();
        (uint128 l,,) = core.getPositionInfo(key.toId(), address(vault), lower, upper, salt);
        (, int24 tick,,) = core.getSlot0(key.toId());
        return vault.state() == AgreementVault.State.Active
            && PoolId.unwrap(key.toId()) == PoolId.unwrap(vault.positionPoolId()) && salt != 0
            && vault.positionId() == keccak256(abi.encode(key.toId(), address(vault), lower, upper, salt))
            && l == vault.positionLiquidity() && l >= 100_000_000_000 && lower >= -887220 && upper <= 887220
            && lower % 60 == 0 && upper % 60 == 0 && lower < upper && lower >= vault.bandLower() - 120
            && lower <= vault.bandLower() && upper <= vault.bandUpper() + 120 && upper >= vault.bandUpper()
            && upper - lower <= 480 && lower <= tick && tick < upper;
    }

    function _advanceTo(uint256 next) private {
        uint256 nowTime = block.timestamp;
        require(next >= nowTime);
        if (_actualQualification()) {
            uint256 end = vault.scheduledEnd();
            expected += (next < end ? next : end) - nowTime;
        }
        vm.warp(next);
        _checkProjection();
    }

    function _checkProjection() private view {
        (bool qualifies,) = hook.qualification();
        require(qualifies == _actualQualification(), "actual C1 qualification");
        require(hook.projectedSeconds() == expected && expected <= 300, "independent projection");
    }

    function _persist() private {
        vm.prank(DONOR);
        require(hook.checkpoint() == expected && hook.qualifyingSeconds() == expected, "independent checkpoint");
        _checkProjection();
    }

    function _flags(uint8 expectedFailures) private view {
        (bool qualified, uint8 failures) = hook.qualification();
        require(failures == expectedFailures && qualified == (failures == 0), "qualification predicates");
    }

    function testExternalSwapsInterruptAndRestore180Seconds() public {
        _active();
        _advanceTo(10_090);
        _swap(120);
        require(hook.observedTick() == 120 && hook.qualifyingSeconds() == 90);
        _flags(hook.TICK_OUTSIDE());
        _advanceTo(10_210);
        _swap(0);
        _flags(0);
        require(hook.qualifyingSeconds() == 90);
        _advanceTo(10_300);
        _flags(hook.PERIOD_ENDED());
        vault.finalizeExpiry();
        require(expected == 180 && hook.qualifyingSeconds() == 180 && hook.lastCheckpoint() == 10_300);
        _advanceTo(10_390);
        _swap(121);
        _persist();
    }

    function testPassiveProjectionPartitionAndLateExpiry() public {
        _active();
        uint256 snapshot = vm.snapshotState();
        _advanceTo(10_350);
        require(hook.qualifyingSeconds() == 0 && expected == 300);
        vault.finalizeExpiry();
        uint256 single = hook.qualifyingSeconds();
        require(vm.revertToStateAndDelete(snapshot));
        for (uint256 i = 1; i <= 300; i += 13) {
            _advanceTo(10_000 + i);
            _persist();
            _persist();
        }
        _advanceTo(10_350);
        _swap(-30); // First ended observation, before the late finalizer.
        require(hook.stopped() && hook.qualifyingSeconds() == single && single == 300);
        vault.finalizeExpiry();
        _persist();
        require(hook.lastCheckpoint() == vault.scheduledEnd());
    }

    function testNoServiceBeforeActivationAndStopAt120() public {
        _ready();
        _advanceTo(10_050);
        _swap(7);
        _persist();
        require(hook.start() == 0 && hook.lastCheckpoint() == 0);
        (, uint8 flags) = hook.qualification();
        require(flags & hook.NOT_ACTIVATED() != 0);
        vault.activate(h);
        require(hook.start() == 10_050 && hook.lastCheckpoint() == 10_050 && hook.qualifyingSeconds() == 0);
        _advanceTo(10_170);
        faults.mockCallRevert(address(core), "", hex"bad0");
        vault.terminate();
        _flags(hook.STOPPED());
        faults.clearMockedCalls();
        _advanceTo(10_200);
        _swap(120);
        vault.terminate();
        vault.exitLiquidity();
        vault.withdrawIdle();
        _advanceTo(10_380);
        _persist();
        require(hook.lastCheckpoint() == 10_170 && expected == 120 && hook.positionId() == 0);
    }

    function _remove(uint128 amount) private {
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        vm.prank(MANAGER);
        vault.remove(id, amount, bounds);
    }

    function _add(uint128 amount) private {
        bytes32 id = vault.positionId();
        int24 lower = vault.positionLower();
        int24 upper = vault.positionUpper();
        AgreementVault.Bounds memory bounds = _bounds();
        vm.prank(MANAGER);
        vault.add(id, lower, upper, amount, bounds);
    }

    function _rerange(int24 lower, int24 upper) private {
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        vm.prank(MANAGER);
        vault.rerange(id, lower, upper, SEED, bounds);
    }

    function testFullRemovalPreservesOldIntervalAndReopeningUsesFreshSalt() public {
        _active();
        bytes32 oldId = vault.positionId();
        _advanceTo(10_100);
        _remove(SEED);
        require(
            vault.positionId() == 0 && hook.positionId() == 0 && _liquidity(address(vault), bytes32(uint256(1))) == 0
        );
        _flags(
            hook.NO_MATCHING_POSITION() | hook.BELOW_MINIMUM() | hook.BAND_NOT_COVERED() | hook.RANGE_NOT_PERMITTED()
                | hook.TICK_OUTSIDE()
        );
        uint256 credited = hook.qualifyingSeconds();
        if (credited != expected) revert OldIntervalLost(expected, credited);
        require(expected == 100);
        _advanceTo(10_150);
        _add(SEED);
        require(
            hook.positionId() == vault.positionId() && hook.positionId() != oldId
                && hook.positionSalt() == bytes32(uint256(2))
        );
        _advanceTo(10_180);
        _remove(1);
        _flags(hook.BELOW_MINIMUM());
        _advanceTo(10_210);
        _add(1);
        _flags(0);
        _advanceTo(10_340);
        vault.finalizeExpiry();
        require(hook.qualifyingSeconds() == expected && expected == 220);
    }

    function testUnrelatedCorePositionContributesZeroWhileEmpty() public {
        _active();
        _advanceTo(10_040);
        _remove(SEED);
        PoolKey memory other = key;
        other.hooks = IHooks(address(0));
        core.initialize(other, 1 << 96);
        CoreSeedHarness otherOwner = new CoreSeedHarness(core, other);
        a.mint(address(otherOwner), PRINCIPAL);
        b.mint(address(otherOwner), PRINCIPAL);
        otherOwner.add(-120, 120, SEED);
        (uint128 otherL,,) = core.getPositionInfo(other.toId(), address(otherOwner), -120, 120, bytes32(0));
        require(otherL == SEED && hook.positionId() == 0 && hook.observedLiquidity() == 0);
        _advanceTo(10_350);
        vault.finalizeExpiry();
        require(hook.qualifyingSeconds() == expected && expected == 40);
    }

    function testExtendedRangeStoredTickEdgesAndSameTimestampChanges() public {
        _active();
        _advanceTo(10_030);
        _swap(120);
        _flags(hook.TICK_OUTSIDE());
        _rerange(-180, 180);
        _flags(0);
        require(hook.observedTick() == 120 && hook.qualifyingSeconds() == 30);
        _advanceTo(10_060);
        _swap(180);
        _flags(hook.TICK_OUTSIDE());
        _advanceTo(10_090);
        _swap(-181);
        _swap(-180);
        _flags(0);
        require(hook.observedTick() == -180 && hook.qualifyingSeconds() == 60);
        _advanceTo(10_120);
        vault.terminate();
        require(hook.qualifyingSeconds() == expected && expected == 90);
    }

    function testClockWritesAuthenticateVaultAndInitializationIsSingleUse() public {
        _active();
        vm.expectRevert(ServiceHook.NotVault.selector);
        hook.stopClock();
        vm.expectRevert(ServiceHook.NotVault.selector);
        hook.installPosition(-180, 180, bytes32(uint256(9)), SEED);
        vm.expectRevert(ServiceHook.NotVault.selector);
        hook.beforeAdjustment();
        vm.expectRevert(ServiceHook.NotVault.selector);
        hook.initializeClock(-120, 120, bytes32(uint256(1)), SEED, 99999);
        vm.expectRevert(ServiceHook.InvalidClockState.selector);
        vm.prank(address(vault));
        hook.initializeClock(-120, 120, bytes32(uint256(1)), SEED, 99999);
        _advanceTo(10_301);
        _persist();
    }

    function testFuzzReconcileSequence(uint256 seed) public {
        _active();
        // Fixture inventory for feasible movements in either direction across many successive swaps.
        _give(a, address(vault), 2 * PRINCIPAL);
        _give(b, address(vault), 2 * PRINCIPAL);
        uint256 time = vault.start();
        for (uint256 i; i < 24; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            time += seed % 13;
            _advanceTo(time);
            uint256 op = (seed >> 16) % 6;
            uint128 l = vault.positionLiquidity();
            if (op == 0 || op == 1) {
                int24 target = int24(int256((seed >> 32) % 341) - 170);
                _swap(target);
                _persist();
            } else if (op == 2 || time < (vault.lastAdjustment() == 0 ? vault.start() : vault.lastAdjustment()) + 30) {
                _persist();
            } else if (l == 0) {
                _add(SEED);
            } else if (op == 3) {
                _remove(l);
            } else if (op == 4) {
                if (l < SEED) _add(SEED - l);
                else _remove(1);
            } else {
                int24 edge = vault.positionUpper() == 120 ? int24(180) : int24(120);
                _rerange(-edge, edge);
            }
            _checkProjection();
            require(
                hook.qualifyingSeconds() == expected && hook.positionId() == vault.positionId(), "post-action state"
            );
        }
        if (seed % 2 == 0) {
            vault.terminate();
        } else {
            _advanceTo(vault.scheduledEnd() + 19);
            vault.finalizeExpiry();
        }
        require(hook.qualifyingSeconds() == expected, "close");
        _advanceTo(vault.scheduledEnd() + 60);
        _persist();
    }
}
