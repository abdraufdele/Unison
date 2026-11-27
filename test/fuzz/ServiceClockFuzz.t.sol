// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ClockFixture} from "../fixtures/ClockFixture.sol";

contract ClockFuzzTest is ClockFixture {
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
