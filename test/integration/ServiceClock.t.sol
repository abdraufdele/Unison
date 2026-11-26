// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ServiceHook} from "../../src/ServiceHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CoreSeedHarness} from "../fixtures/CoreSeedHarness.sol";
import {ClockFixture} from "../fixtures/ClockFixture.sol";

contract ServiceClockTest is ClockFixture {
    using StateLibrary for IPoolManager;
    error OldIntervalLost(uint256 expectedSeconds, uint256 persistedSeconds);

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
}
