// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IC1Token} from "../../src/ExactToken.sol";

/// @dev Test only. Acknowledges the two dispatched callbacks; admits every LP and measures no service.
contract TestOnlySeedHook {
    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }
}

/// @dev Isolated payer/position owner for actual core deltas. All transfers use this harness's own mock tokens.
contract CoreSeedHarness is IUnlockCallback {
    IPoolManager private immutable manager;
    address private immutable fixture;
    PoolKey private key;
    bool private executing;

    constructor(IPoolManager core, PoolKey memory fixtureKey) {
        manager = core;
        key = fixtureKey;
        fixture = msg.sender;
    }

    function add(int24 lower, int24 upper, uint128 liquidity) external returns (BalanceDelta principal) {
        return _unlock(abi.encode(lower, upper, liquidity, uint160(0)));
    }

    function swapDownTo(uint160 limit) external {
        require(limit != 0);
        _unlock(abi.encode(int24(0), int24(0), uint128(0), limit));
    }

    function _unlock(bytes memory operation) private returns (BalanceDelta) {
        require(msg.sender == fixture && !executing);
        executing = true;
        bytes memory result = manager.unlock(operation);
        executing = false;
        return abi.decode(result, (BalanceDelta));
    }

    function unlockCallback(bytes calldata operation) external returns (bytes memory) {
        require(msg.sender == address(manager) && executing);
        (int24 lower, int24 upper, uint128 liquidity, uint160 limit) =
            abi.decode(operation, (int24, int24, uint128, uint160));
        BalanceDelta net;
        BalanceDelta fees;
        if (limit == 0) {
            (net, fees) = manager.modifyLiquidity(
                key, IPoolManager.ModifyLiquidityParams(lower, upper, int256(uint256(liquidity)), bytes32(0)), ""
            );
        } else {
            net = manager.swap(key, IPoolManager.SwapParams(true, -int256(1e15), limit), "");
        }
        _settle(key.currency0, net.amount0());
        _settle(key.currency1, net.amount1());
        return abi.encode(net - fees);
    }

    function _settle(Currency currency, int128 delta) private {
        if (delta < 0) {
            manager.sync(currency);
            uint128 due = uint128(-delta);
            require(IC1Token(Currency.unwrap(currency)).transfer(address(manager), due));
            require(manager.settle() == due);
        } else if (delta > 0) {
            manager.take(currency, address(this), uint128(delta));
        }
    }
}
