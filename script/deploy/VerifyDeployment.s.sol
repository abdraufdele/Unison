// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementRecord} from "../helpers/AgreementRecord.sol";

contract VerifyDeployment is AgreementRecord {
    /// @notice Authenticate the mined deployment and return the current terms and position identifiers.
    function run() external view returns (bytes32 terms, bytes32 position) {
        Agreement memory a = agreement();
        return (a.hash, a.position);
    }
}
