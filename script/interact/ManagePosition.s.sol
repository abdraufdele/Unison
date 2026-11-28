// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementRecord} from "../helpers/AgreementRecord.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";

contract ManagePosition is AgreementRecord {
    /// @notice Read signed tick bounds and exact base-unit limits from the operator's JSON order.
    function order(Agreement memory a) internal view returns (AgreementVault.Bounds memory b) {
        string memory json = vm.readFile(vm.envString("BOUNDS_CONFIG"));
        int256 lo = vm.parseJsonInt(json, ".tickLower");
        int256 hi = vm.parseJsonInt(json, ".tickUpper");
        require(lo >= type(int24).min && hi <= type(int24).max && lo < hi, "tick bounds");
        b = AgreementVault.Bounds(
            a.hash,
            vm.parseJsonUint(json, ".validFrom"),
            vm.envUint("DEADLINE"),
            int24(lo),
            int24(hi),
            vm.parseJsonUint(json, ".maxInput0"),
            vm.parseJsonUint(json, ".maxInput1"),
            vm.parseJsonUint(json, ".minOutput0"),
            vm.parseJsonUint(json, ".minOutput1")
        );
    }

    /// @notice Increase the reviewed position by the specified liquidity with capped gross inputs.
    function add(int24 lower, int24 upper, uint128 liquidity) external {
        Agreement memory a = action();
        AgreementVault.Bounds memory b = order(a);
        vm.broadcast(msg.sender);
        a.vault.add(a.position, lower, upper, liquidity, b);
    }

    /// @notice Remove the specified liquidity subject to the supplied minimum outputs.
    function remove(uint128 liquidity) external {
        Agreement memory a = action();
        AgreementVault.Bounds memory b = order(a);
        vm.broadcast(msg.sender);
        a.vault.remove(a.position, liquidity, b);
    }

    /// @notice Atomically retire the reviewed position and open the bounded replacement.
    function rerange(int24 lower, int24 upper, uint128 liquidity) external {
        Agreement memory a = action();
        AgreementVault.Bounds memory b = order(a);
        vm.broadcast(msg.sender);
        a.vault.rerange(a.position, lower, upper, liquidity, b);
    }
}
