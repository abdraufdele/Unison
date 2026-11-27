// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OpeningBand} from "../../src/OpeningBand.sol";

contract OpeningBandFuzzTest {
    uint256 private constant MAX_ANSWER = 33514072460913245910620992844148187695034543842;

    /// @notice Sample bounded feed answers and check that each selected edge covers its price and is minimal.
    function testFuzzCoverageAndMinimality(uint160 seed, uint8 shift) public pure {
        uint256 answer = 1 + ((uint256(seed) >> (shift % 160)) % MAX_ANSWER);
        (int24 lo, int24 hi) = OpeningBand.calculate(answer, 60, 100, 480);
        require(lo % 60 == 0 && hi % 60 == 0 && hi > lo && hi - lo <= 480, "usable width");
        // No C1 percentage target equals a grid price. All grid floors below are independently certified.
        require(OpeningBand.scaledGridFloor(lo) < answer * 99, "lower coverage");
        require(OpeningBand.scaledGridFloor(lo + 60) >= answer * 99, "lower minimality");
        require(OpeningBand.scaledGridFloor(hi) >= answer * 101, "upper coverage");
        require(OpeningBand.scaledGridFloor(hi - 60) < answer * 101, "upper minimality");
    }
}
