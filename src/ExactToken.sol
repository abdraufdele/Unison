// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IC1Token {
    /// @notice Read the token's decimal scale used to validate the C1 denomination.
    function decimals() external view returns (uint8);
    /// @notice Read actual token base units held by the specified account.
    function balanceOf(address account) external view returns (uint256);
    /// @notice Debit the caller and credit the recipient in token base units.
    function transfer(address recipient, uint256 amount) external returns (bool);
    /// @notice Spend an allowance to move base units from the sender to the specified recipient.
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

/// @dev C1 supports tokens with truthful balances and exact, non-rebasing transfers.
library ExactToken {
    error TransferFailed(address token);
    error UnexpectedBalance(address token, address account);

    /// @notice Collect an authorized deposit and verify both balance deltas in base units.
    function pull(IC1Token token, address sender, address recipient, uint256 amount) internal {
        moveExactly(token, sender, recipient, amount, abi.encodeCall(token.transferFrom, (sender, recipient, amount)));
    }

    /// @notice Send a nonzero payout from this custodian and verify exact receipt.
    function pay(IC1Token token, address recipient, uint256 amount) internal {
        if (amount != 0) {
            moveExactly(token, address(this), recipient, amount, abi.encodeCall(token.transfer, (recipient, amount)));
        }
    }

    /// @notice Execute the prepared ERC-20 transfer and reconcile exact debits and credits around the call.
    function moveExactly(IC1Token token, address sender, address recipient, uint256 amount, bytes memory data) private {
        uint256 senderBefore = token.balanceOf(sender);
        uint256 recipientBefore = token.balanceOf(recipient);
        (bool ok, bytes memory result) = address(token).call(data);
        if (!ok || (result.length != 0 && (result.length != 32 || abi.decode(result, (uint256)) != 1))) {
            revert TransferFailed(address(token));
        }
        checkDebit(token, sender, senderBefore, amount);
        checkReceipt(token, recipient, recipientBefore, amount);
    }

    /// @notice Compare the sender's actual balance decrease with the agreed base-unit amount.
    function checkDebit(IC1Token token, address sender, uint256 beforeBalance, uint256 amount) internal view {
        uint256 afterBalance = token.balanceOf(sender);
        if (afterBalance > beforeBalance || beforeBalance - afterBalance != amount) {
            revert UnexpectedBalance(address(token), sender);
        }
    }

    /// @notice Compare the recipient's actual increase with the agreed base-unit amount.
    function checkReceipt(IC1Token token, address recipient, uint256 beforeBalance, uint256 amount) internal view {
        uint256 afterBalance = token.balanceOf(recipient);
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != amount) {
            revert UnexpectedBalance(address(token), recipient);
        }
    }
}

abstract contract CustodyLock {
    error ReentrantCall();
    bool private entered;

    modifier nonReentrant() {
        if (entered) revert ReentrantCall();
        entered = true;
        _;
        entered = false;
    }
}
