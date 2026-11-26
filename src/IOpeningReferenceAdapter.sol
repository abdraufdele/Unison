// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice One fixed observation read. The adapter attests source, denomination and completion.
interface IOpeningReferenceAdapter {
    struct Observation {
        address source;
        address base;
        address quote;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        uint8 feedDecimals;
        int256 answer;
        uint256 updatedAt;
        bool complete;
    }

    /// @notice Read one opening observation including source, denominations, scale, completion and timestamp.
    function observation() external view returns (Observation memory);
}
