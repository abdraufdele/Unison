// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @notice Outward rounding of C1's exact B-base-units per A-base-unit targets.
library OpeningBand {
    uint256 internal constant TARGET_SCALE = 1e10; // 1e8 feed scale times 100 for the percentage.
    int24 internal constant SPACING = 60;
    uint256 private constant SCALE = 4e57;

    error UnsupportedParameters();
    error UnrepresentablePrice();
    error InvalidWidth();
    error UnresolvedComparison();

    /// @notice Round the eight-decimal parity-relative C1 price band outward to usable grid ticks.
    function calculate(uint256 answer, int24 spacing, uint16 halfWidthBps, int24 maxWidth)
        internal
        pure
        returns (int24 lower, int24 upper)
    {
        if (spacing != SPACING || halfWidthBps != 100) revert UnsupportedParameters();
        if (answer == 0 || answer > type(uint256).max / 101) revert UnrepresentablePrice();
        lower = edge(answer * 99, false);
        upper = edge(answer * 101, true);
        if (lower >= upper || upper - lower > maxWidth) revert InvalidWidth();
    }

    /// @dev First grid price >= numerator / TARGET_SCALE. Its predecessor is the floor except at exact equality.
    function edge(uint256 numerator, bool roundUp) internal pure returns (int24) {
        if (numerator == 0) revert UnrepresentablePrice();
        if (numerator == TARGET_SCALE) return 0; // Only equality possible at this target scale.
        int24 below = TickMath.minUsableTick(SPACING) / SPACING - 1;
        int24 above = TickMath.maxUsableTick(SPACING) / SPACING + 1;
        int24 sentinel = above;
        while (above - below > 1) {
            int24 mid = below + (above - below) / 2;
            if (scaledGridFloor(mid * SPACING) >= numerator) above = mid;
            else below = mid;
        }
        // Every positive numerator exceeds the minimum grid price at this scale.
        if (above == sentinel) revert UnrepresentablePrice();
        return (roundUp ? above : below) * SPACING;
    }

    /// @dev Exact floor of 1e10 * (10001/10000)^tick for the C1 grid.
    /// Both directed bounds must certify the same integer. See docs/OPENING-REFERENCE.md.
    function scaledGridFloor(int24 tick) internal pure returns (uint256) {
        if (tick % SPACING != 0 || tick < TickMath.MIN_TICK || tick > TickMath.MAX_TICK) {
            revert UnsupportedParameters();
        }
        uint256 exponent = uint256(int256(tick < 0 ? -tick : tick)) / 2;
        uint256 baseLo;
        uint256 baseHi;
        if (tick < 0) {
            baseLo = SCALE * 10000 / 10001;
            baseHi = baseLo + 1;
        } else {
            baseLo = SCALE / 10000 * 10001;
            baseHi = baseLo;
        }

        uint256 lo = SCALE;
        uint256 hi = SCALE;
        while (exponent != 0) {
            if ((exponent & 1) != 0) {
                lo = FullMath.mulDiv(lo, baseLo, SCALE);
                hi = FullMath.mulDivRoundingUp(hi, baseHi, SCALE);
            }
            exponent >>= 1;
            if (exponent != 0) {
                baseLo = FullMath.mulDiv(baseLo, baseLo, SCALE);
                baseHi = FullMath.mulDivRoundingUp(baseHi, baseHi, SCALE);
            }
        }

        // Rescale sqrt bounds to 1e43. Squaring and dividing by 1e76 gives prices at 1e10.
        lo /= 4e14;
        hi = (hi + 4e14 - 1) / 4e14;
        uint256 result = FullMath.mulDiv(lo, lo, 1e76);
        if (result != FullMath.mulDiv(hi, hi, 1e76)) revert UnresolvedComparison();
        return result;
    }
}
