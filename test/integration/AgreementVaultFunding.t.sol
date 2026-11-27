// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {CompensationEscrow} from "../../src/CompensationEscrow.sol";
import {ExactToken} from "../../src/ExactToken.sol";
import {CustodyFixture, CustodyToken} from "../fixtures/CustodyFixture.sol";
import {Vm} from "../helpers/Vm.sol";

/// @dev Mimics the escrow's read surface, but has no settlement implementation.
contract EscrowLookalike {
    address public vault;
    address public paymentToken;
    address public treasuryRecipient;
    address public managerRecipient;
    uint256 public fundedBudget;
    uint256 public refunded;

    /// @notice Imitate the escrow getters to challenge funding's canonical runtime check.
    constructor(address v, address token, address treasury, address manager) {
        (vault, paymentToken, treasuryRecipient, managerRecipient) = (v, token, treasury, manager);
    }
}

contract AgreementVaultFundingTest is CustodyFixture {
    /// @notice Preload gifts, fund the agreement and compare each actual receipt with its credited amount.
    function testExactDepositsCreditsAndReceiptsWithPriorGifts() public {
        giveTokens(a, address(vault), 11);
        giveTokens(b, address(vault), 22);
        giveTokens(b, address(escrow), 33);
        acceptTerms();
        bytes32 h = vault.termsHash();
        vm.recordLogs();
        vault.fund(h);
        assertCustodyBalances(0, 0, PRINCIPAL + 11, PRINCIPAL + 22, BUDGET + 33);
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

    /// @notice Vary the caller and acceptance records and require full current consent before treasury funding.
    function testBothCurrentAcceptancesAndTreasuryRequired() public {
        bytes32 first = vault.termsHash();
        vm.expectRevert(AgreementVault.NotAccepted.selector);
        vault.fund(first);
        vault.accept(first);
        vm.expectRevert(AgreementVault.NotAccepted.selector);
        vault.fund(first);
        acceptTerms();
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
        assertCustodyBalances(PRINCIPAL, PRINCIPAL + BUDGET, 0, 0, 0);
    }

    /// @notice Try edits and further deposits after funding and check that funded terms stay fixed.
    function testFundedTermsAndApprovalsLocked() public {
        fundFixture();
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
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    /// @notice Fund one second before the exclusive cutoff and verify the full deposit.
    function testFundingAtLastSecond() public {
        vm.warp(vault.activationCutoff() - 1);
        fundFixture();
        require(vault.state() == AgreementVault.State.Funded, "last second");
    }

    /// @notice Try funding at the cutoff and later and require both attempts to fail.
    function testFundingAtAndAfterOriginalCutoff() public {
        acceptTerms();
        bytes32 h = vault.termsHash();
        uint256 deadline = vault.activationCutoff();
        for (uint256 i; i < 2; ++i) {
            vm.warp(deadline + i);
            vm.expectRevert(AgreementVault.CutoffReached.selector);
            vault.fund(h);
        }
        assertCustodyBalances(PRINCIPAL, PRINCIPAL + BUDGET, 0, 0, 0);
    }

    /// @notice Call credit outside the bound vault and verify the escrow rejects it.
    function testOnlyBoundVaultMayCredit() public {
        vm.expectRevert(CompensationEscrow.NotVault.selector);
        escrow.credit(BUDGET);
        fundFixture();
        vm.expectRevert(CompensationEscrow.AlreadyCredited.selector);
        vm.prank(address(vault));
        escrow.credit(BUDGET);
        require(escrow.fundedBudget() == BUDGET, "single credit");
    }

    /// @notice Substitute escrow implementations or beneficiaries and require funding to reject each mismatch.
    function testOnlyCanonicalEscrowWithAllFourBindingsCanReceiveFunding() public {
        expectEscrowRejection(address(0x7000));
        expectEscrowRejection(address(new EscrowLookalike(address(vault), address(b), address(this), MANAGER)));
        expectEscrowRejection(address(new CompensationEscrow(DONOR, b, address(this), MANAGER)));
        expectEscrowRejection(address(new CompensationEscrow(address(vault), a, address(this), MANAGER)));
        expectEscrowRejection(address(new CompensationEscrow(address(vault), b, DONOR, MANAGER)));
        expectEscrowRejection(address(new CompensationEscrow(address(vault), b, address(this), DONOR)));
    }

    /// @notice Try funding with the candidate escrow and require the binding check to reject it.
    function expectEscrowRejection(address candidate) private {
        AgreementVault.Bindings memory bindings = vault.currentTerms().bindings;
        bindings.escrow = candidate;
        vault.revise(bindings);
        acceptTerms();
        assertFundingRollback(abi.encodeWithSelector(AgreementVault.InvalidEscrow.selector));
        require(b.balanceOf(candidate) == 0, "candidate received budget");
    }

    /// @notice Change either actual token denomination and require funding to reject the pair.
    function testWrongDecimalsOfEitherToken() public {
        acceptTerms();
        a.setDecimals(18);
        assertFundingRollback(abi.encodeWithSelector(AgreementVault.InvalidDecimals.selector, address(a)));
        a.setDecimals(6);
        b.setDecimals(8);
        assertFundingRollback(abi.encodeWithSelector(AgreementVault.InvalidDecimals.selector, address(b)));
    }

    /// @notice Break each deposit leg and reconcile the balances after the reverted call.
    function testAnyRevertingLegRollsBack() public {
        acceptTerms();
        expectFailedDeposit(a, address(vault));
        expectFailedDeposit(b, address(vault));
        expectFailedDeposit(b, address(escrow));
        vault.fund(vault.termsHash());
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    /// @notice Block one transfer route and check that funding is atomic.
    function expectFailedDeposit(CustodyToken token, address to) private {
        token.setFault(address(this), to, CustodyToken.Fault.Revert);
        assertFundingRollback(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(token)));
        token.setFault(address(this), to, CustodyToken.Fault.None);
    }

    /// @notice Gift tokens to custody before funding and verify that treasury still owes the full deposit.
    function testGiftsCannotCoverMissingTreasuryBalance() public {
        require(a.transfer(address(vault), 1));
        require(b.transfer(address(escrow), 1));
        acceptTerms();
        assertFundingRollback(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(a)));
        a.mint(address(this), 1);
        // Enough B for the principal, one unit short for the budget, even with the escrow gift.
        assertFundingRollback(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
    }

    /// @notice Underapprove each leg, including the combined B liability, and verify that funding fails.
    function testVaultAllowancesMustCoverEachLegIncludingTotalB() public {
        acceptTerms();
        a.approve(address(vault), PRINCIPAL - 1);
        assertFundingRollback(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(a)));
        a.approve(address(vault), PRINCIPAL);
        b.approve(address(vault), PRINCIPAL - 1);
        assertFundingRollback(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        b.approve(address(vault), PRINCIPAL + BUDGET - 1);
        assertFundingRollback(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
    }

    /// @notice Inject false success or incorrect balance deltas and compare all custody accounts after rollback.
    function testFalseReturnShortReceiptAndUnexpectedDebitRollback() public {
        acceptTerms();
        b.mint(address(this), 1);
        giveTokens(b, address(escrow), BUDGET);
        b.setFault(address(this), address(escrow), CustodyToken.Fault.FalseReturn);
        assertFundingRollback(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        b.setFault(address(this), address(escrow), CustodyToken.Fault.ShortReceipt);
        assertFundingRollback(
            abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(escrow))
        );
        b.setFault(address(this), address(escrow), CustodyToken.Fault.ExtraDebit);
        assertFundingRollback(abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(this)));
        b.setFault(address(this), address(escrow), CustodyToken.Fault.ChangePriorBalance);
        assertFundingRollback(abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(vault)));
    }

    /// @notice Compare balances and funding credits around the specified failing deposit.
    function assertFundingRollback(bytes memory reason) private {
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
        assertCustodyBalances(treasuryA, treasuryB, vaultA, vaultB, escrowB);
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

    /// @notice Return malformed success data from a token and require the deposit to revert.
    function testMalformedSuccessWordRollsBack() public {
        acceptTerms();
        b.setFault(address(this), address(escrow), CustodyToken.Fault.InvalidReturn);
        assertFundingRollback(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
    }

    /// @notice Complete an exact transfer without return data and verify the credited deposit.
    function testNoReturnTokenWithExactBalances() public {
        a.setFault(address(this), address(vault), CustodyToken.Fault.NoReturn);
        fundFixture();
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    /// @notice Probe reentry during both B transfers and require that the original funding remains atomic.
    function testFundingRejectsTreasuryReentryAcrossBothBTransfers() public {
        b.setProbe(this);
        fundFixture();
        require(blockedCalls == 4 && vault.state() == AgreementVault.State.Funded, "funding callbacks");
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }
}
