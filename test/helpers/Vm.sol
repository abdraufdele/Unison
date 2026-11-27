// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Test-only Foundry cheatcodes. All state assertions use the vault's public interface.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    /// @notice Move the Foundry fixture's timestamp to the specified second.
    function warp(uint256 timestamp) external;
    /// @notice Select the test chain used in the terms commitment.
    function chainId(uint256 id) external;
    /// @notice Set the test account nonce for a deterministic CREATE vector.
    function setNonce(address account, uint64 nonce) external;
    /// @notice Use the supplied actor for the next external call.
    function prank(address caller) external;
    /// @notice Require the next operation to revert under the selected Foundry expectation.
    function expectRevert(bytes calldata reason) external;
    /// @notice Require the next operation to revert under the selected Foundry expectation.
    function expectRevert(bytes4 selector) external;
    /// @notice Capture the full EVM fixture before branching into an independent trial.
    function snapshotState() external returns (uint256);
    /// @notice Restore the snapshot and discard the saved branch.
    function revertToStateAndDelete(uint256 snapshot) external returns (bool);
    /// @notice Begin collecting EVM logs for independent receipt checks.
    function recordLogs() external;
    /// @notice Return the logs captured since the last recording request.
    function getRecordedLogs() external returns (Log[] memory);
}
