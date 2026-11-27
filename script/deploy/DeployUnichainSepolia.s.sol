// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeploymentBase} from "../helpers/DeploymentBase.sol";

contract DeployUnichainSepolia is DeploymentBase {
    /// @notice Check the sepolia dependencies and the direct treasury creator before preparing any transaction.
    function preflight() external view {
        loadConfig(1301, "sepolia");
    }

    /// @notice Create and verify one unaccepted C1 draft using the sepolia configuration.
    function run() external {
        deploy(1301, "sepolia");
    }
}
