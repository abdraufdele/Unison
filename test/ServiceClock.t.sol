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

    /// @notice Derive qualification independently from core tick, range and actual position liquidity.
    function coreQualifies() private view returns (bool) {
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

    /// @notice Credit the model's prior qualification before moving the fixture clock.
    function advanceClockModel(uint256 next) private {
        uint256 nowTime = block.timestamp;
        require(next >= nowTime);
        if (coreQualifies()) {
            uint256 end = vault.scheduledEnd();
            expected += (next < end ? next : end) - nowTime;
        }
        vm.warp(next);
        assertClockProjection();
    }

    /// @notice Compare projected service seconds with the independent interval sum.
    function assertClockProjection() private view {
        (bool qualifies,) = hook.qualification();
        require(qualifies == coreQualifies(), "actual C1 qualification");
        require(hook.projectedSeconds() == expected && expected <= 300, "independent projection");
    }

    /// @notice Persist the current interval and compare stored and projected time.
    function checkpointAndCompare() private {
        vm.prank(DONOR);
        require(hook.checkpoint() == expected && hook.qualifyingSeconds() == expected, "independent checkpoint");
        assertClockProjection();
    }

    /// @notice Compare qualification and its failure bitmask with the expected predicates.
    function assertQualificationFlags(uint8 expectedFailures) private view {
        (bool qualified, uint8 failures) = hook.qualification();
        require(failures == expectedFailures && qualified == (failures == 0), "qualification predicates");
    }

    /// @notice Move price out of range and back with external swaps and reconcile 180 qualifying seconds.
    function testExternalSwapsInterruptAndRestore180Seconds() public {
        activateFixture();
        advanceClockModel(10_090);
        swapToTick(120);
        require(hook.observedTick() == 120 && hook.qualifyingSeconds() == 90);
        assertQualificationFlags(hook.TICK_OUTSIDE());
        advanceClockModel(10_210);
        swapToTick(0);
        assertQualificationFlags(0);
        require(hook.qualifyingSeconds() == 90);
        advanceClockModel(10_300);
        assertQualificationFlags(hook.PERIOD_ENDED());
        vault.finalizeExpiry();
        require(expected == 180 && hook.qualifyingSeconds() == 180 && hook.lastCheckpoint() == 10_300);
        advanceClockModel(10_390);
        swapToTick(121);
        checkpointAndCompare();
    }

    /// @notice Partition passive service with checkpoints and verify late persistence clips at the original end.
    function testPassiveProjectionPartitionAndLateExpiry() public {
        activateFixture();
        uint256 snapshot = vm.snapshotState();
        advanceClockModel(10_350);
        require(hook.qualifyingSeconds() == 0 && expected == 300);
        vault.finalizeExpiry();
        uint256 single = hook.qualifyingSeconds();
        require(vm.revertToStateAndDelete(snapshot));
        for (uint256 i = 1; i <= 300; i += 13) {
            advanceClockModel(10_000 + i);
            checkpointAndCompare();
            checkpointAndCompare();
        }
        advanceClockModel(10_350);
        swapToTick(-30); // First ended observation, before the late finalizer.
        require(hook.stopped() && hook.qualifyingSeconds() == single && single == 300);
        vault.finalizeExpiry();
        checkpointAndCompare();
        require(hook.lastCheckpoint() == vault.scheduledEnd());
    }

    /// @notice Read before activation and after a 120-second stop and verify only the active interval earns.
    function testNoServiceBeforeActivationAndStopAt120() public {
        prepareFundedFixture();
        advanceClockModel(10_050);
        swapToTick(7);
        checkpointAndCompare();
        require(hook.start() == 0 && hook.lastCheckpoint() == 0);
        (, uint8 flags) = hook.qualification();
        require(flags & hook.NOT_ACTIVATED() != 0);
        vault.activate(h);
        require(hook.start() == 10_050 && hook.lastCheckpoint() == 10_050 && hook.qualifyingSeconds() == 0);
        advanceClockModel(10_170);
        faults.mockCallRevert(address(core), "", hex"bad0");
        vault.terminate();
        assertQualificationFlags(hook.STOPPED());
        faults.clearMockedCalls();
        advanceClockModel(10_200);
        swapToTick(120);
        vault.terminate();
        vault.exitLiquidity();
        vault.withdrawIdle();
        advanceClockModel(10_380);
        checkpointAndCompare();
        require(hook.lastCheckpoint() == 10_170 && expected == 120 && hook.positionId() == 0);
    }

    /// @notice Remove the specified raw liquidity using the current position and execution bounds.
    function removeAsManager(uint128 amount) private {
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.remove(id, amount, bounds);
    }

    /// @notice Increase seed-range liquidity as the named manager under current execution bounds.
    function addAsManager(uint128 amount) private {
        bytes32 id = vault.positionId();
        int24 lower = vault.positionLower();
        int24 upper = vault.positionUpper();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.add(id, lower, upper, amount, bounds);
    }

    /// @notice Replace the active range using the named manager and accepted position identity.
    function rerangeAsManager(int24 lower, int24 upper) private {
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.rerange(id, lower, upper, SEED, bounds);
    }

    /// @notice Remove all liquidity after service, reopen on fresh salt and check that the old interval was credited.
    function testFullRemovalPreservesOldIntervalAndReopeningUsesFreshSalt() public {
        activateFixture();
        bytes32 oldId = vault.positionId();
        advanceClockModel(10_100);
        removeAsManager(SEED);
        require(
            vault.positionId() == 0 && hook.positionId() == 0
                && seedRangeLiquidity(address(vault), bytes32(uint256(1))) == 0
        );
        assertQualificationFlags(
            hook.NO_MATCHING_POSITION() | hook.BELOW_MINIMUM() | hook.BAND_NOT_COVERED() | hook.RANGE_NOT_PERMITTED()
                | hook.TICK_OUTSIDE()
        );
        uint256 credited = hook.qualifyingSeconds();
        if (credited != expected) revert OldIntervalLost(expected, credited);
        require(expected == 100);
        advanceClockModel(10_150);
        addAsManager(SEED);
        require(
            hook.positionId() == vault.positionId() && hook.positionId() != oldId
                && hook.positionSalt() == bytes32(uint256(2))
        );
        advanceClockModel(10_180);
        removeAsManager(1);
        assertQualificationFlags(hook.BELOW_MINIMUM());
        advanceClockModel(10_210);
        addAsManager(1);
        assertQualificationFlags(0);
        advanceClockModel(10_340);
        vault.finalizeExpiry();
        require(hook.qualifyingSeconds() == expected && expected == 220);
    }

    /// @notice Leave the attributed identity empty while other core liquidity exists and require zero service.
    function testUnrelatedCorePositionContributesZeroWhileEmpty() public {
        activateFixture();
        advanceClockModel(10_040);
        removeAsManager(SEED);
        PoolKey memory other = key;
        other.hooks = IHooks(address(0));
        core.initialize(other, 1 << 96);
        CoreSeedHarness otherOwner = new CoreSeedHarness(core, other);
        a.mint(address(otherOwner), PRINCIPAL);
        b.mint(address(otherOwner), PRINCIPAL);
        otherOwner.add(-120, 120, SEED);
        (uint128 otherL,,) = core.getPositionInfo(other.toId(), address(otherOwner), -120, 120, bytes32(0));
        require(otherL == SEED && hook.positionId() == 0 && hook.observedLiquidity() == 0);
        advanceClockModel(10_350);
        vault.finalizeExpiry();
        require(hook.qualifyingSeconds() == expected && expected == 40);
    }

    /// @notice Cross both extended range edges at controlled times and verify half-open and zero-time transitions.
    function testExtendedRangeStoredTickEdgesAndSameTimestampChanges() public {
        activateFixture();
        advanceClockModel(10_030);
        swapToTick(120);
        assertQualificationFlags(hook.TICK_OUTSIDE());
        rerangeAsManager(-180, 180);
        assertQualificationFlags(0);
        require(hook.observedTick() == 120 && hook.qualifyingSeconds() == 30);
        advanceClockModel(10_060);
        swapToTick(180);
        assertQualificationFlags(hook.TICK_OUTSIDE());
        advanceClockModel(10_090);
        swapToTick(-181);
        swapToTick(-180);
        assertQualificationFlags(0);
        require(hook.observedTick() == -180 && hook.qualifyingSeconds() == 60);
        advanceClockModel(10_120);
        vault.terminate();
        require(hook.qualifyingSeconds() == expected && expected == 90);
    }

    /// @notice Try direct clock writes and repeat initialization and require the vault and lifecycle guards.
    function testClockWritesAuthenticateVaultAndInitializationIsSingleUse() public {
        activateFixture();
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
        advanceClockModel(10_301);
        checkpointAndCompare();
    }

    /// @notice Generate a bounded sequence of price and liquidity changes and compare the independent interval sum.
    function testFuzzReconcileSequence(uint256 seed) public {
        activateFixture();
        // Fixture inventory for feasible movements in either direction across many successive swaps.
        giveTokens(a, address(vault), 2 * PRINCIPAL);
        giveTokens(b, address(vault), 2 * PRINCIPAL);
        uint256 time = vault.start();
        for (uint256 i; i < 24; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            time += seed % 13;
            advanceClockModel(time);
            uint256 op = (seed >> 16) % 6;
            uint128 l = vault.positionLiquidity();
            if (op == 0 || op == 1) {
                int24 target = int24(int256((seed >> 32) % 341) - 170);
                swapToTick(target);
                checkpointAndCompare();
            } else if (op == 2 || time < (vault.lastAdjustment() == 0 ? vault.start() : vault.lastAdjustment()) + 30) {
                checkpointAndCompare();
            } else if (l == 0) {
                addAsManager(SEED);
            } else if (op == 3) {
                removeAsManager(l);
            } else if (op == 4) {
                if (l < SEED) addAsManager(SEED - l);
                else removeAsManager(1);
            } else {
                int24 edge = vault.positionUpper() == 120 ? int24(180) : int24(120);
                rerangeAsManager(-edge, edge);
            }
            assertClockProjection();
            require(
                hook.qualifyingSeconds() == expected && hook.positionId() == vault.positionId(), "post-action state"
            );
        }
        if (seed % 2 == 0) {
            vault.terminate();
        } else {
            advanceClockModel(vault.scheduledEnd() + 19);
            vault.finalizeExpiry();
        }
        require(hook.qualifyingSeconds() == expected, "close");
        advanceClockModel(vault.scheduledEnd() + 60);
        checkpointAndCompare();
    }
}
