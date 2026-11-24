// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CustodyLock, ExactToken, IC1Token} from "./ExactToken.sol";

interface ICancellation {
    function cancelled() external view returns (bool);
}

/// @notice One C1 budget. Constructor-only storage bindings give every instance the same verifiable runtime code.
contract CompensationEscrow is CustodyLock {
    address public vault;
    IC1Token public paymentToken;
    address public treasuryRecipient;
    address public managerRecipient;
    uint256 public fundedBudget;
    uint256 public refunded;

    error NotVault();
    error AlreadyCredited();
    error NotCancelled();

    event BudgetCredited(address indexed token, uint256 amount);
    event BudgetRefunded(address indexed recipient, uint256 amount);

    constructor(address agreementVault, IC1Token token, address treasury, address manager) {
        vault = agreementVault;
        paymentToken = token;
        treasuryRecipient = treasury;
        managerRecipient = manager;
    }

    /// @dev Only the bound vault can call this after verifying the treasury-to-escrow deposit.
    function credit(uint256 amount) external nonReentrant {
        if (msg.sender != vault) revert NotVault();
        if (fundedBudget != 0) revert AlreadyCredited();
        fundedBudget = amount;
        emit BudgetCredited(address(paymentToken), amount);
    }

    function refundable() external view returns (uint256) {
        return ICancellation(vault).cancelled() ? fundedBudget - refunded : 0;
    }

    function refund() external nonReentrant returns (uint256 amount) {
        if (!ICancellation(vault).cancelled()) revert NotCancelled();
        amount = fundedBudget - refunded;
        if (amount == 0) return 0;
        refunded += amount;
        ExactToken.pay(paymentToken, treasuryRecipient, amount);
        emit BudgetRefunded(treasuryRecipient, amount);
    }
}
