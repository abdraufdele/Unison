// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeploymentBase} from "../helpers/DeploymentBase.sol";

contract DeployLocal is DeploymentBase {
    /// @notice Check the local dependencies and the direct treasury creator before preparing any transaction.
    function preflight() external view {
        loadConfig(31337, "local");
    }

    /// @notice Create and verify one unaccepted C1 draft using the local configuration.
    function run() external {
        deploy(31337, "local");
    }
}
