// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IC1Token {
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

/// @dev C1 supports tokens with truthful balances and exact, non-rebasing transfers.
library ExactToken {
    error TransferFailed(address token);
    error UnexpectedBalance(address token, address account);

    function pull(IC1Token token, address sender, address recipient, uint256 amount) internal {
        _move(token, sender, recipient, amount, abi.encodeCall(token.transferFrom, (sender, recipient, amount)));
    }

    function pay(IC1Token token, address recipient, uint256 amount) internal {
        if (amount != 0) {
            _move(token, address(this), recipient, amount, abi.encodeCall(token.transfer, (recipient, amount)));
        }
    }

    function _move(IC1Token token, address sender, address recipient, uint256 amount, bytes memory data) private {
        uint256 senderBefore = token.balanceOf(sender);
        uint256 recipientBefore = token.balanceOf(recipient);
        (bool ok, bytes memory result) = address(token).call(data);
        if (!ok || (result.length != 0 && (result.length != 32 || abi.decode(result, (uint256)) != 1))) {
            revert TransferFailed(address(token));
        }
        checkDebit(token, sender, senderBefore, amount);
        checkReceipt(token, recipient, recipientBefore, amount);
    }

    function checkDebit(IC1Token token, address sender, uint256 beforeBalance, uint256 amount) internal view {
        uint256 afterBalance = token.balanceOf(sender);
        if (afterBalance > beforeBalance || beforeBalance - afterBalance != amount) {
            revert UnexpectedBalance(address(token), sender);
        }
    }

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
