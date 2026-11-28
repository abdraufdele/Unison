// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementRecord} from "../helpers/AgreementRecord.sol";

contract SettlementActions is AgreementRecord {
    /// @notice Persist the old qualifying interval and observe current core state.
    function checkpoint() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.hook.checkpoint();
    }

    /// @notice Pay the accrued unpaid entitlement to the fixed manager.
    function claim() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.escrow.claim();
    }

    /// @notice Freeze the period early as treasury without moving either asset.
    function terminate() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.vault.terminate();
    }

    /// @notice Persist the effective scheduled stop after expiry.
    function finalizeExpiry() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.vault.finalizeExpiry();
    }

    /// @notice Remove the closed position into the vault independently of payment.
    function exitLiquidity() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.vault.exitLiquidity();
    }

    /// @notice Withdraw both idle principal assets to the fixed treasury.
    function withdrawIdle() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.vault.withdrawIdle();
    }

    /// @notice Return terminal unearned compensation while preserving manager reserves.
    function refund() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.escrow.refund();
    }
}
