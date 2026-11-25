// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ActiveFixture} from "./ActiveFixture.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

/// @dev Quote each leg from the actual price and position fee-growth snapshots before mutation.
abstract contract PositionAccountingFixture is ActiveFixture {
    using StateLibrary for IPoolManager;

    function _principal(int24 lower, int24 upper, uint128 l, bool roundUp) internal view returns (uint256, uint256) {
        (uint160 sqrt,,,) = core.getSlot0(key.toId());
        uint160 lo = TickMath.getSqrtPriceAtTick(lower);
        uint160 hi = TickMath.getSqrtPriceAtTick(upper);
        uint160 clipped = sqrt < lo ? lo : (sqrt > hi ? hi : sqrt);
        return (
            SqrtPriceMath.getAmount0Delta(clipped, hi, l, roundUp),
            SqrtPriceMath.getAmount1Delta(lo, clipped, l, roundUp)
        );
    }

    function _fees(int24 lower, int24 upper) internal view returns (uint256, uint256) {
        (uint128 l, uint256 lastA, uint256 lastB) =
            core.getPositionInfo(key.toId(), address(vault), lower, upper, vault.positionSalt());
        (uint256 growthA, uint256 growthB) = core.getFeeGrowthInside(key.toId(), lower, upper);
        return (FullMath.mulDiv(growthA - lastA, l, 1 << 128), FullMath.mulDiv(growthB - lastB, l, 1 << 128));
    }
}
