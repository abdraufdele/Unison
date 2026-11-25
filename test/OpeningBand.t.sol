// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OpeningBand} from "../src/OpeningBand.sol";
import {Vm} from "./AgreementVaultAcceptance.t.sol";

contract OpeningBandTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant MAX_ANSWER = 33514072460913245910620992844148187695034543842;

    function testFeedVectorsAndRepresentableExtremes() public pure {
        _vector(1, -184320, -184080);
        _vector(1_000_000, -46200, -45900);
        _vector(100_000_000, -120, 120);
        _vector(125_000_000, 2100, 2340);
        _vector(MAX_ANSWER - 1, 886980, 887220);
        _vector(MAX_ANSWER, 886980, 887220);
    }

    function testAdjacentFeedAnswersStraddlingNegativeZeroAndPositiveGridPrices() public pure {
        // Independent integer oracle, immediately adjacent feed answers on each side of each crossing.
        _vector(95128016, -660, -360);
        _vector(95128017, -600, -360);
        _vector(93244292, -840, -600);
        _vector(93244293, -840, -540);
        _vector(101010101, -60, 240);
        _vector(101010102, 0, 240);
        _vector(99009900, -240, 0);
        _vector(99009901, -240, 60);
        _vector(107255895, 540, 840);
        _vector(107255896, 600, 840);
        _vector(105132015, 360, 600);
        _vector(105132016, 360, 660);
    }

    function _vector(uint256 answer, int24 expectedLo, int24 expectedHi) private pure {
        (int24 lo, int24 hi) = OpeningBand.calculate(answer, 60, 100, 480);
        require(lo == expectedLo && hi == expectedHi, "wrong feed vector");
    }

    function testSyntheticExactBoundaryAndNeighbors() public pure {
        // A target numerator on the 1e10 lattice, independent of a feed answer.
        require(OpeningBand.edge(1e10, false) == 0 && OpeningBand.edge(1e10, true) == 0, "exact parity");
        require(OpeningBand.edge(1e10 - 1, false) == -60 && OpeningBand.edge(1e10 - 1, true) == 0, "below");
        require(OpeningBand.edge(1e10 + 1, false) == 0 && OpeningBand.edge(1e10 + 1, true) == 60, "above");
    }

    function calculate(uint256 answer, int24 spacing, uint16 bps, int24 maxWidth) external pure {
        OpeningBand.calculate(answer, spacing, bps, maxWidth);
    }

    function testRejectsUnrepresentableOverflowAndSyntheticInvalidParameters() public {
        vm.expectRevert(OpeningBand.UnrepresentablePrice.selector);
        this.calculate(0, 60, 100, 480);
        vm.expectRevert(OpeningBand.UnrepresentablePrice.selector);
        this.calculate(MAX_ANSWER + 1, 60, 100, 480);
        vm.expectRevert(OpeningBand.UnrepresentablePrice.selector);
        this.calculate(type(uint256).max, 60, 100, 480);
        vm.expectRevert(OpeningBand.UnsupportedParameters.selector);
        this.calculate(1e8, 0, 100, 480);
        vm.expectRevert(OpeningBand.UnsupportedParameters.selector);
        this.calculate(1e8, 60, 0, 480);
        vm.expectRevert(OpeningBand.InvalidWidth.selector);
        this.calculate(1e8, 60, 100, 239);
    }

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

    // SHA-256 of ascending uint256 grid floors, independently produced by scripts/check_opening_grid.py.
    function testEveryNegativeGridPrice() public pure {
        _checkGrid(-887220, -60, 0xab1e5d73507da3e8a8b62e1165998e44d909377944d489842c36a1cfca95017e);
    }

    function testEveryLowerNonnegativeGridPrice() public pure {
        _checkGrid(0, 443580, 0x9fd4602ec31429f49b22e24e3b7478a77be94cf54bc118e5a3184d6cc335571e);
    }

    function testEveryUpperPositiveGridPrice() public pure {
        _checkGrid(443640, 887220, 0x2ffccc1efbb52c09c7483658f8299ec6e1462357d3b97abdf090b0b145ebb9f3);
    }

    function _checkGrid(int24 first, int24 last, bytes32 expected) private pure {
        uint256[] memory words = new uint256[](uint24((last - first) / 60) + 1);
        uint256 i;
        for (int24 t = first; t <= last; t += 60) {
            words[i++] = OpeningBand.scaledGridFloor(t);
        }
        require(sha256(abi.encodePacked(words)) == expected, "grid differs from rational oracle");
    }
}
