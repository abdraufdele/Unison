// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ServiceHook} from "../../src/ServiceHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

library ServicePoolFixture {
    /// @notice Install the exact flag-mined service hook and check the resulting vault and pool bindings.
    function install(address boundVault, IPoolManager core, Currency c0, Currency c1)
        internal
        returns (ServiceHook hook, PoolKey memory key)
    {
        bytes32 initHash =
            keccak256(abi.encodePacked(type(ServiceHook).creationCode, abi.encode(boundVault, core, c0, c1)));
        bytes32 salt;
        address predicted;
        for (uint256 i; i < 1_000_000; ++i) {
            salt = bytes32(i);
            predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initHash)))));
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK == Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG) {
                break;
            }
        }
        hook = new ServiceHook{salt: salt}(boundVault, core, c0, c1);
        require(
            address(hook) == predicted
                && (uint160(predicted) & Hooks.ALL_HOOK_MASK)
                    == (Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG)
                && address(hook).codehash == keccak256(type(ServiceHook).runtimeCode),
            "CREATE2 product"
        );
        key = PoolKey(c0, c1, 3000, 60, IHooks(predicted));
        require(
            PoolId.unwrap(hook.poolId()) == PoolId.unwrap(key.toId()) && hook.poolManager() == core
                && hook.vault() == boundVault
        );
    }
}
