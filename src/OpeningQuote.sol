// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OpeningBand} from "./OpeningBand.sol";
import {SeedPool} from "./SeedPool.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/// @notice Stateless opening calculations shared by the vault's preview and activation paths.
contract OpeningQuote {
    /// @notice Return the outward grid edges for the accepted C1 reference answer and width.
    function band(uint256 answer, int24 spacing, uint16 halfWidthBps, int24 maxWidth)
        external
        pure
        returns (int24 lower, int24 upper)
    {
        return OpeningBand.calculate(answer, spacing, halfWidthBps, maxWidth);
    }

    /// @notice Quote the gross base-unit cost of the proposed liquidity against actual core state.
    function seed(IPoolManager core, PoolKey calldata key, int24 lower, int24 upper, uint128 liquidity)
        external
        view
        returns (SeedPool.Quote memory)
    {
        return SeedPool.inspect(core, key, lower, upper, liquidity);
    }
}
