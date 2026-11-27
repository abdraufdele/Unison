// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeploymentBase} from "../helpers/DeploymentBase.sol";

contract DeployUnichainMainnet is DeploymentBase {
    /// @notice Check the mainnet dependencies and the direct treasury creator before preparing any transaction.
    function preflight() external view {
        loadConfig(130, "mainnet");
    }

    /// @notice Create and verify one unaccepted C1 draft using the mainnet configuration.
    function run() external {
        deploy(130, "mainnet");
    }
}
