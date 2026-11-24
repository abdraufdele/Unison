// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../src/AgreementVault.sol";
import {CompensationEscrow} from "../src/CompensationEscrow.sol";
import {ExactToken} from "../src/ExactToken.sol";
import {CustodyFixture, CustodyToken} from "./fixtures/CustodyFixture.sol";
import {Vm} from "./AgreementVaultAcceptance.t.sol";

/// @dev Mimics the escrow's read surface, but has no settlement implementation.
contract EscrowLookalike {
    address public vault;
    address public paymentToken;
    address public treasuryRecipient;
    address public managerRecipient;
    uint256 public fundedBudget;
    uint256 public refunded;

    constructor(address v, address token, address treasury, address manager) {
        (vault, paymentToken, treasuryRecipient, managerRecipient) = (v, token, treasury, manager);
    }
}

contract AgreementVaultFundingTest is CustodyFixture {
    function testExactDepositsCreditsAndReceiptsWithPriorGifts() public {
        _give(a, address(vault), 11);
        _give(b, address(vault), 22);
        _give(b, address(escrow), 33);
        _accept();
        bytes32 h = vault.termsHash();
        vm.recordLogs();
        vault.fund(h);
        _balances(0, 0, PRINCIPAL + 11, PRINCIPAL + 22, BUDGET + 33);
        require(vault.fundedPrincipal0() == PRINCIPAL && vault.fundedPrincipal1() == PRINCIPAL, "principal credits");
        require(escrow.fundedBudget() == BUDGET && escrow.refundable() == 0 && escrow.refunded() == 0, "funded rights");
        require(
            a.allowance(address(this), address(vault)) == 0 && b.allowance(address(this), address(vault)) == 0,
            "allowances"
        );
        require(vault.state() == AgreementVault.State.Funded, "funded state");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 2 && logs[0].emitter == address(escrow) && logs[1].emitter == address(vault), "receipts");
        require(
            logs[0].topics[0] == keccak256("BudgetCredited(address,uint256)")
                && address(uint160(uint256(logs[0].topics[1]))) == address(b),
            "budget token"
        );
        require(abi.decode(logs[0].data, (uint256)) == BUDGET, "budget receipt");
        require(
            logs[1].topics[0] == keccak256("Funded(uint256,bytes32,address,uint256,uint256,uint256)")
                && uint256(logs[1].topics[1]) == vault.revision() && logs[1].topics[2] == h
                && address(uint160(uint256(logs[1].topics[3]))) == address(escrow),
            "funded commitment"
        );
        require(keccak256(logs[1].data) == keccak256(abi.encode(PRINCIPAL, PRINCIPAL, BUDGET)), "funded amounts");
    }

    function testBothCurrentAcceptancesAndTreasuryRequired() public {
        bytes32 first = vault.termsHash();
        vm.expectRevert(AgreementVault.NotAccepted.selector);
        vault.fund(first);
        vault.accept(first);
        vm.expectRevert(AgreementVault.NotAccepted.selector);
        vault.fund(first);
        _accept();
        vault.revise(vault.currentTerms().bindings);
        bytes32 h = vault.termsHash();
        vm.prank(MANAGER);
        vault.accept(h);
        vm.expectRevert(AgreementVault.NotAccepted.selector);
        vault.fund(h);
        vault.accept(h);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, first, h));
        vault.fund(first);
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(MANAGER);
        vault.fund(h);
        _balances(PRINCIPAL, PRINCIPAL + BUDGET, 0, 0, 0);
    }

    function testFundedTermsAndApprovalsLocked() public {
        _fund();
        bytes32 h = vault.termsHash();
        AgreementVault.Bindings memory bindings = vault.currentTerms().bindings;
        vm.expectRevert(AgreementVault.TermsClosed.selector);
        vault.fund(h);
        vm.expectRevert(AgreementVault.TermsClosed.selector);
        vault.revise(bindings);
        vm.expectRevert(AgreementVault.TermsClosed.selector);
        vault.accept(h);
        vm.expectRevert(AgreementVault.TermsClosed.selector);
        vm.prank(MANAGER);
        vault.accept(h);
        require(
            vault.termsHash() == h && vault.managerAcceptedRevision() == vault.revision()
                && vault.treasuryAcceptedRevision() == vault.revision(),
            "consent changed"
        );
        _balances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    function testFundingAtLastSecond() public {
        vm.warp(vault.activationCutoff() - 1);
        _fund();
        require(vault.state() == AgreementVault.State.Funded, "last second");
    }

    function testFundingAtAndAfterOriginalCutoff() public {
        _accept();
        bytes32 h = vault.termsHash();
        uint256 deadline = vault.activationCutoff();
        for (uint256 i; i < 2; ++i) {
            vm.warp(deadline + i);
            vm.expectRevert(AgreementVault.CutoffReached.selector);
            vault.fund(h);
        }
        _balances(PRINCIPAL, PRINCIPAL + BUDGET, 0, 0, 0);
    }

    function testOnlyBoundVaultMayCredit() public {
        vm.expectRevert(CompensationEscrow.NotVault.selector);
        escrow.credit(BUDGET);
        _fund();
        vm.expectRevert(CompensationEscrow.AlreadyCredited.selector);
        vm.prank(address(vault));
        escrow.credit(BUDGET);
        require(escrow.fundedBudget() == BUDGET, "single credit");
    }

    function testOnlyCanonicalEscrowWithAllFourBindingsCanReceiveFunding() public {
        _rejectEscrow(address(0x7000));
        _rejectEscrow(address(new EscrowLookalike(address(vault), address(b), address(this), MANAGER)));
        _rejectEscrow(address(new CompensationEscrow(DONOR, b, address(this), MANAGER)));
        _rejectEscrow(address(new CompensationEscrow(address(vault), a, address(this), MANAGER)));
        _rejectEscrow(address(new CompensationEscrow(address(vault), b, DONOR, MANAGER)));
        _rejectEscrow(address(new CompensationEscrow(address(vault), b, address(this), DONOR)));
    }

    function _rejectEscrow(address candidate) private {
        AgreementVault.Bindings memory bindings = vault.currentTerms().bindings;
        bindings.escrow = candidate;
        vault.revise(bindings);
        _accept();
        _expectAtomicFailure(abi.encodeWithSelector(AgreementVault.InvalidEscrow.selector));
        require(b.balanceOf(candidate) == 0, "candidate received budget");
    }

    function testWrongDecimalsOfEitherToken() public {
        _accept();
        a.setDecimals(18);
        _expectAtomicFailure(abi.encodeWithSelector(AgreementVault.InvalidDecimals.selector, address(a)));
        a.setDecimals(6);
        b.setDecimals(8);
        _expectAtomicFailure(abi.encodeWithSelector(AgreementVault.InvalidDecimals.selector, address(b)));
    }

    function testAnyRevertingLegRollsBack() public {
        _accept();
        _failedLeg(a, address(vault));
        _failedLeg(b, address(vault));
        _failedLeg(b, address(escrow));
        vault.fund(vault.termsHash());
        _balances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    function _failedLeg(CustodyToken token, address to) private {
        token.setFault(address(this), to, CustodyToken.Fault.Revert);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(token)));
        token.setFault(address(this), to, CustodyToken.Fault.None);
    }

    function testGiftsCannotCoverMissingTreasuryBalance() public {
        require(a.transfer(address(vault), 1));
        require(b.transfer(address(escrow), 1));
        _accept();
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(a)));
        a.mint(address(this), 1);
        // Enough B for the principal, one unit short for the budget, even with the escrow gift.
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
    }

    function testVaultAllowancesMustCoverEachLegIncludingTotalB() public {
        _accept();
        a.approve(address(vault), PRINCIPAL - 1);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(a)));
        a.approve(address(vault), PRINCIPAL);
        b.approve(address(vault), PRINCIPAL - 1);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        b.approve(address(vault), PRINCIPAL + BUDGET - 1);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
    }

    function testFalseReturnShortReceiptAndUnexpectedDebitRollback() public {
        _accept();
        b.mint(address(this), 1);
        _give(b, address(escrow), BUDGET);
        b.setFault(address(this), address(escrow), CustodyToken.Fault.FalseReturn);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        b.setFault(address(this), address(escrow), CustodyToken.Fault.ShortReceipt);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(escrow)));
        b.setFault(address(this), address(escrow), CustodyToken.Fault.ExtraDebit);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(this)));
        b.setFault(address(this), address(escrow), CustodyToken.Fault.ChangePriorBalance);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(vault)));
    }

    function _expectAtomicFailure(bytes memory reason) private {
        uint256 treasuryA = a.balanceOf(address(this));
        uint256 treasuryB = b.balanceOf(address(this));
        uint256 vaultA = a.balanceOf(address(vault));
        uint256 vaultB = b.balanceOf(address(vault));
        uint256 escrowB = b.balanceOf(address(escrow));
        uint256 allowedA = a.allowance(address(this), address(vault));
        uint256 allowedB = b.allowance(address(this), address(vault));
        bytes32 h = vault.termsHash();
        vm.expectRevert(reason);
        vault.fund(h);
        _balances(treasuryA, treasuryB, vaultA, vaultB, escrowB);
        require(
            a.allowance(address(this), address(vault)) == allowedA
                && b.allowance(address(this), address(vault)) == allowedB,
            "allowance rollback"
        );
        require(
            vault.state() == AgreementVault.State.Accepted && vault.fundedPrincipal0() == 0
                && vault.fundedPrincipal1() == 0,
            "principal rollback"
        );
        require(escrow.fundedBudget() == 0 && escrow.refunded() == 0 && escrow.refundable() == 0, "escrow rollback");
    }

    function testMalformedSuccessWordRollsBack() public {
        _accept();
        b.setFault(address(this), address(escrow), CustodyToken.Fault.InvalidReturn);
        _expectAtomicFailure(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
    }

    function testNoReturnTokenWithExactBalances() public {
        a.setFault(address(this), address(vault), CustodyToken.Fault.NoReturn);
        _fund();
        _balances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    function testFundingRejectsTreasuryReentryAcrossBothBTransfers() public {
        b.setProbe(this);
        _fund();
        require(blockedCalls == 4 && vault.state() == AgreementVault.State.Funded, "funding callbacks");
        _balances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }
}
