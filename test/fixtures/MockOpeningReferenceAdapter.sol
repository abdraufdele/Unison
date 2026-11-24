// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IOpeningReferenceAdapter} from "../../src/IOpeningReferenceAdapter.sol";

/// @dev Local fixture only. Any test caller may publish any asserted observation.
contract MockOpeningReferenceAdapter is IOpeningReferenceAdapter {
    Observation private latest;

    function publish(Observation calldata next) external {
        latest = next;
    }

    function observation() external view returns (Observation memory) {
        return latest;
    }
}
