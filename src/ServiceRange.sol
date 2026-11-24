// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @dev Fixed C1 rules shared by the accepted terms, add admission and service qualification.
library ServiceRange {
    int24 internal constant SPACING = 60;
    int24 internal constant WIDTH = 480;
    int24 internal constant EXTENSION = 120;
    uint128 internal constant MIN_LIQUIDITY = 100_000_000_000;

    function covers(int24 lower, int24 upper, int24 bandLower, int24 bandUpper) internal pure returns (bool) {
        return lower <= bandLower && upper >= bandUpper;
    }

    function permitted(int24 lower, int24 upper, int24 bandLower, int24 bandUpper) internal pure returns (bool) {
        return lower >= bandLower - EXTENSION && upper <= bandUpper + EXTENSION
            && lower >= TickMath.minUsableTick(SPACING) && upper <= TickMath.maxUsableTick(SPACING)
            && lower % SPACING == 0 && upper % SPACING == 0 && lower < upper && upper - lower <= WIDTH;
    }
}
