// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

/// @notice Read the pinned core's state and quote the gross principal for one in-range C1 seed.
library SeedPool {
    using StateLibrary for IPoolManager;

    struct Quote {
        IPoolManager manager;
        PoolKey key;
        PoolId id;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
    }

    error InvalidPoolConfiguration();
    error UninitializedPool(PoolId id);
    error TickOutsideBand(int24 tick, int24 lower, int24 upper);
    error InvalidSeedRange();
    error TickCapacityExceeded();

    function inspect(IPoolManager manager, PoolKey memory key, int24 lower, int24 upper, uint128 liquidity)
        internal
        view
        returns (Quote memory q)
    {
        uint160 flags = uint160(address(key.hooks)) & Hooks.ALL_HOOK_MASK;
        if (
            key.currency0 >= key.currency1 || key.fee != 3000 || key.tickSpacing != 60
                || address(key.hooks).code.length == 0
                || flags != (Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG)
        ) {
            revert InvalidPoolConfiguration();
        }
        if (
            lower >= upper || lower < TickMath.minUsableTick(key.tickSpacing)
                || upper > TickMath.maxUsableTick(key.tickSpacing) || lower % key.tickSpacing != 0
                || upper % key.tickSpacing != 0
        ) revert InvalidSeedRange();

        q.manager = manager;
        q.key = key;
        q.id = key.toId();
        uint24 lpFee;
        (q.sqrtPriceX96, q.tick,, lpFee) = manager.getSlot0(q.id);
        if (q.sqrtPriceX96 == 0) revert UninitializedPool(q.id);
        if (lpFee != key.fee) revert InvalidPoolConfiguration();
        if (q.tick < lower || q.tick >= upper) revert TickOutsideBand(q.tick, lower, upper);

        (uint128 grossLower,) = manager.getTickLiquidity(q.id, lower);
        (uint128 grossUpper,) = manager.getTickLiquidity(q.id, upper);
        uint128 limit = Pool.tickSpacingToMaxLiquidityPerTick(key.tickSpacing);
        if (uint256(grossLower) + liquidity > limit || uint256(grossUpper) + liquidity > limit) {
            revert TickCapacityExceeded();
        }

        // Core branches on the stored tick, then prices each leg at the actual sqrt ratio.
        // A downward crossing can leave that ratio exactly at the upper edge while tick == upper - 1.
        q.liquidity = liquidity;
        q.amount0 = SqrtPriceMath.getAmount0Delta(q.sqrtPriceX96, TickMath.getSqrtPriceAtTick(upper), liquidity, true);
        q.amount1 = SqrtPriceMath.getAmount1Delta(TickMath.getSqrtPriceAtTick(lower), q.sqrtPriceX96, liquidity, true);
    }
}
