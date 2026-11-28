// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementRecord} from "../helpers/AgreementRecord.sol";
import {DemoReference} from "../fixtures/DemoAssets.sol";

contract FixtureOpening is AgreementRecord {
    /// @notice Refresh only the named publisher's local or Sepolia demo observation before activation.
    function refresh() external {
        Agreement memory a = action();
        string memory json = vm.readFile(vm.envString("MANIFEST"));
        require(
            (block.chainid == 31337 || block.chainid == 1301) && vm.parseJsonBool(json, ".fixtureAssets"),
            "fixture network"
        );
        DemoReference adapter = DemoReference(a.terms.bindings.referenceAdapter);
        require(
            msg.sender == a.terms.treasury && adapter.publisher() == msg.sender && a.vault.start() == 0
                && !a.vault.cancelled(),
            "fixture publisher/state"
        );
        vm.broadcast(msg.sender);
        adapter.refresh();
    }
}
