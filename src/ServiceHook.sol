// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/// @notice C1 seed admission. Constructor-only bindings give every genuine instance the same runtime hash.
contract ServiceHook {
    address public vault;
    IPoolManager public poolManager;
    PoolId public poolId;
    bytes32 public pendingSeed;

    error InvalidBinding();
    error NotVault();
    error WrongCoreOrPool();
    error InvalidSeedContext();

    constructor(address ownerVault, IPoolManager core, Currency token0, Currency token1) {
        if (
            ownerVault == address(0) || address(core) == address(0) || token0.isAddressZero() || token0 >= token1
                || (uint160(address(this)) & Hooks.ALL_HOOK_MASK)
                    != (Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG)
        ) {
            revert InvalidBinding();
        }
        vault = ownerVault;
        poolManager = core;
        poolId = PoolKey(token0, token1, 3000, 60, IHooks(address(this))).toId();
    }

    /// @dev The vault calls this inside its authenticated seed unlock, immediately before the single add leg.
    function armSeed(IPoolManager.ModifyLiquidityParams calldata params) external {
        if (msg.sender != vault) revert NotVault();
        if (pendingSeed != 0 || params.liquidityDelta <= 0) revert InvalidSeedContext();
        pendingSeed = keccak256(abi.encode(params));
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external returns (bytes4) {
        _authenticate(key);
        if (sender != vault) revert NotVault();
        if (pendingSeed == 0 || pendingSeed != keccak256(abi.encode(params))) revert InvalidSeedContext();
        delete pendingSeed;
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        view
        returns (bytes4, int128)
    {
        _authenticate(key);
        return (IHooks.afterSwap.selector, 0);
    }

    function _authenticate(PoolKey calldata key) private view {
        if (msg.sender != address(poolManager) || PoolId.unwrap(key.toId()) != PoolId.unwrap(poolId)) {
            revert WrongCoreOrPool();
        }
    }
}
