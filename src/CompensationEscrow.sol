// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CustodyLock, ExactToken, IC1Token} from "./ExactToken.sol";

import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {ServiceHook} from "./ServiceHook.sol";

interface ISettlementVault {
    function settlementContext() external view returns (ServiceHook clock, uint256 duration, bool terminal);
}

/// @notice One C1 budget. Constructor-only storage bindings give every instance the same verifiable runtime code.
contract CompensationEscrow is CustodyLock {
    address public vault;
    IC1Token public paymentToken;
    address public treasuryRecipient;
    address public managerRecipient;
    uint256 public fundedBudget;
    uint256 public claimed;
    uint256 public refunded;

    error NotVault();
    error AlreadyCredited();
    error NotTerminal();
    error ClaimUnavailable();
    error InvalidServiceTime();

    event BudgetCredited(address indexed token, uint256 amount);
    event CompensationClaimed(address indexed recipient, uint256 amount);
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

    /// @notice Earned units as of chain time. The clock exposes persisted Q separately.
    function earned() public view returns (uint256) {
        (ServiceHook clock, uint256 duration,) = ISettlementVault(vault).settlementContext();
        return _projectedEarned(clock, duration);
    }

    function claimable() public view returns (uint256) {
        return earned() - claimed;
    }

    function reserved() external view returns (uint256) {
        return claimable();
    }

    function accounted() external view returns (uint256) {
        return fundedBudget - claimed - refunded;
    }

    function refundable() external view returns (uint256) {
        (ServiceHook clock, uint256 duration, bool terminal) = ISettlementVault(vault).settlementContext();
        return terminal ? _refundDue(_projectedEarned(clock, duration)) : 0;
    }

    function _projectedEarned(ServiceHook clock, uint256 duration) private view returns (uint256) {
        return address(clock) == address(0) ? 0 : _earned(clock.projectedSeconds(), duration);
    }

    function _checkpointEarned(ServiceHook clock, uint256 duration) private returns (uint256) {
        return address(clock) == address(0) ? 0 : _earned(clock.checkpoint(), duration);
    }

    function _earned(uint256 qualifyingSeconds, uint256 duration) private view returns (uint256) {
        if (duration == 0 || qualifyingSeconds > duration) revert InvalidServiceTime();
        // The accepted vault credits the exact full budget before it can activate.
        return FullMath.mulDiv(fundedBudget, qualifyingSeconds, duration);
    }

    function _refundDue(uint256 totalEarned) private view returns (uint256) {
        return fundedBudget - totalEarned - refunded;
    }

    function claim() external nonReentrant returns (uint256 amount) {
        (ServiceHook clock, uint256 duration, bool terminal) = ISettlementVault(vault).settlementContext();
        if (address(clock) == address(0) && !terminal) revert ClaimUnavailable();
        amount = _checkpointEarned(clock, duration) - claimed;
        if (amount == 0) return 0;
        claimed += amount;
        ExactToken.pay(paymentToken, managerRecipient, amount);
        emit CompensationClaimed(managerRecipient, amount);
    }

    function refund() external nonReentrant returns (uint256 amount) {
        (ServiceHook clock, uint256 duration, bool terminal) = ISettlementVault(vault).settlementContext();
        if (!terminal) revert NotTerminal();
        amount = _refundDue(_checkpointEarned(clock, duration));
        if (amount == 0) return 0;
        refunded += amount;
        ExactToken.pay(paymentToken, treasuryRecipient, amount);
        emit BudgetRefunded(treasuryRecipient, amount);
    }
}
