// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ActiveFixture} from "./ActiveFixture.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

abstract contract ClockFixture is ActiveFixture {
    using StateLibrary for IPoolManager;

    // Independent interval oracle. Read the vault lifecycle and exact core key at the LEFT
    // endpoint. Advance simulated time and integrate that predicate before the next action.
    uint256 internal expected;

    /// @notice Derive qualification independently from core tick, range and actual position liquidity.
    function coreQualifies() internal view returns (bool) {
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
    function advanceClockModel(uint256 next) internal {
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
    function assertClockProjection() internal view {
        (bool qualifies,) = hook.qualification();
        require(qualifies == coreQualifies(), "actual C1 qualification");
        require(hook.projectedSeconds() == expected && expected <= 300, "independent projection");
    }

    /// @notice Persist the current interval and compare stored and projected time.
    function checkpointAndCompare() internal {
        vm.prank(DONOR);
        require(hook.checkpoint() == expected && hook.qualifyingSeconds() == expected, "independent checkpoint");
        assertClockProjection();
    }

    /// @notice Increase seed-range liquidity as the named manager under current execution bounds.
    function addAsManager(uint128 amount) internal {
        bytes32 id = vault.positionId();
        int24 lower = vault.positionLower();
        int24 upper = vault.positionUpper();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.add(id, lower, upper, amount, bounds);
    }

    /// @notice Remove the specified raw liquidity using the current position and execution bounds.
    function removeAsManager(uint128 amount) internal {
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.remove(id, amount, bounds);
    }

    /// @notice Replace the active range using the named manager and accepted position identity.
    function rerangeAsManager(int24 lower, int24 upper) internal {
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.rerange(id, lower, upper, SEED, bounds);
    }
}
