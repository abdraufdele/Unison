// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {Vm} from "../helpers/Vm.sol";
import {ConsentFixture} from "../fixtures/ConsentFixture.sol";

contract AgreementVaultAcceptanceTest is ConsentFixture {
    /// @notice Submit a draft edit from the fixture treasury.
    function reviseBindings(AgreementVault.Bindings memory b) private {
        vm.prank(TREASURY);
        vault.revise(b);
    }

    /// @notice Compare the published proposal with an independently encoded commitment and both fixed beneficiaries.
    function testPublishedC1CommitmentAndRecipients() public view {
        AgreementVault.Terms memory t = vault.currentTerms();
        require(t.vault == address(vault) && t.treasury == TREASURY && t.manager == MANAGER, "identities");
        require(t.treasuryRecipient == TREASURY && t.managerRecipient == MANAGER, "recipients");
        require(t.paymentToken == t.bindings.token1 && t.bindings.escrow != t.vault, "budget custody");
        require(t.referenceBase == t.bindings.token0 && t.referenceQuote == t.bindings.token1, "orientation");
        // Independently encoded 42 static ABI words for this fixture (chain 31337, treasury CREATE nonce 1).
        bytes32 knownHash = 0xa0408781342948aa46a35f31e2eb0e27bdf237d5d16f63c89915663f3d3162e0;
        require(vault.termsHash() == knownHash, "C1 commitment vector");
        require(keccak256(abi.encode(vault.TERMS_SCHEMA(), t)) == knownHash, "public terms reconstruct commitment");
        assertConsentState(1, 0, 0, AgreementVault.State.Draft);
    }

    /// @notice Accept twice as treasury and verify that only a distinct manager decision completes consent.
    function testTreasuryFirstAndRepeatedAcceptance() public {
        bytes32 h = vault.termsHash();
        vm.recordLogs();
        acceptTerms(TREASURY, h);
        assertConsentState(1, 1, 0, AgreementVault.State.Draft);
        acceptTerms(TREASURY, h);
        acceptTerms(MANAGER, h);
        acceptTerms(MANAGER, h);
        assertConsentState(1, 1, 1, AgreementVault.State.Accepted);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 2, "one receipt per role");
        for (uint256 i; i < 2; ++i) {
            bytes32[] memory topics = logs[i].topics;
            require(logs[i].emitter == address(vault) && topics.length == 4, "receipt");
            require(topics[0] == keccak256("PartyAccepted(uint256,bytes32,address)"), "event");
            require(topics[1] == bytes32(uint256(1)) && topics[2] == h, "revision and hash");
            require(topics[3] == bytes32(uint256(uint160(i == 0 ? TREASURY : MANAGER))), "caller");
        }
    }

    /// @notice Let the manager consent first and check the draft remains open for the treasury.
    function testManagerAcceptanceLeavesDraftUntilTreasuryConsents() public {
        bytes32 h = vault.termsHash();
        acceptTerms(MANAGER, h);
        assertConsentState(1, 0, 1, AgreementVault.State.Draft);
        acceptTerms(TREASURY, h);
        assertConsentState(1, 1, 1, AgreementVault.State.Accepted);
    }

    /// @notice Submit a stranger's consent and draft edit and verify that neither changes the proposal.
    function testUnauthorizedAcceptanceAndRevision() public {
        bytes32 h = vault.termsHash();
        vm.expectRevert(AgreementVault.NotParty.selector);
        vault.accept(h);
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vault.revise(initialBindings());
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(MANAGER);
        vault.revise(initialBindings());
        assertConsentState(1, 0, 0, AgreementVault.State.Draft);
        require(vault.termsHash() == h, "unauthorized call changed terms");
    }

    /// @notice Reuse a hash from another vault with identical parties and verify the vault domain prevents replay.
    function testOtherVaultHashRejectedEvenWithSamePartiesIdTimeAndTerms() public {
        AgreementVault other = createVault(ID, MANAGER, initialBindings());
        bytes32 foreign = other.termsHash();
        bytes32 current = vault.termsHash();
        require(foreign != current, "domain collision");
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, foreign, current));
        acceptTerms(TREASURY, foreign);
        assertConsentState(1, 0, 0, AgreementVault.State.Draft);
    }

    /// @notice Change and restore bindings and require two fresh decisions even when the values match the original.
    function testRevisionClearsBothAndRestoringTermsRequiresFreshDecisions() public {
        bytes32 first = vault.termsHash();
        acceptTerms(TREASURY, first);
        acceptTerms(MANAGER, first);
        AgreementVault.Bindings memory updated = initialBindings();
        updated.hook = address(0x6001);
        reviseBindings(updated);
        assertConsentState(2, 0, 0, AgreementVault.State.Draft);
        bytes32 second = vault.termsHash();
        require(vault.currentTerms().bindings.hook == updated.hook, "revised hook not exposed");
        acceptTerms(MANAGER, second);
        reviseBindings(initialBindings());
        bytes32 third = vault.termsHash();
        require(third != first && third != second, "reused commitment");
        assertConsentState(3, 0, 0, AgreementVault.State.Draft);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, first, third));
        acceptTerms(TREASURY, first);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, second, third));
        acceptTerms(MANAGER, second);
        acceptTerms(MANAGER, third);
        assertConsentState(3, 0, 3, AgreementVault.State.Draft);
        acceptTerms(TREASURY, third);
        assertConsentState(3, 3, 3, AgreementVault.State.Accepted);
    }

    // Compare alternative revision-two proposals on the SAME instance at the SAME timestamp.
    /// @notice Return a revision-two commitment for comparing independent single-field changes.
    function revisedTermsHash(AgreementVault.Bindings memory next) private returns (bytes32) {
        uint256 snapshot = vm.snapshotState();
        reviseBindings(next);
        bytes32 h = vault.termsHash();
        require(vm.revertToStateAndDelete(snapshot), "snapshot restore");
        return h;
    }

    /// @notice Vary one address at a time at revision two and compare the resulting commitments.
    function testEachRevisableFieldAffectsCommitmentAtSameRevision() public {
        AgreementVault.Bindings memory b = initialBindings();
        bytes32 base = revisedTermsHash(b);
        b.poolManager = address(0x3001);
        require(revisedTermsHash(b) != base, "pool manager omitted");
        b = initialBindings();
        b.token0 = address(0x4001);
        require(revisedTermsHash(b) != base, "token0 omitted");
        b = initialBindings();
        b.token1 = address(0x5001);
        require(revisedTermsHash(b) != base, "token1 omitted");
        b = initialBindings();
        b.hook = address(0x6001);
        require(revisedTermsHash(b) != base, "hook omitted");
        b = initialBindings();
        b.escrow = address(0x7001);
        require(revisedTermsHash(b) != base, "escrow omitted");
        b = initialBindings();
        b.referenceAdapter = address(0x8001);
        require(revisedTermsHash(b) != base, "adapter omitted");
        b = initialBindings();
        b.referenceSource = address(0x9001);
        require(revisedTermsHash(b) != base, "source omitted");
    }

    /// @notice Edit at the last eligible second and check the original parties, domain and cutoff.
    function testNoOpRevisionAtLastSecondKeepsControllerDomainAndDeadline() public {
        bytes32 oldHash = vault.termsHash();
        acceptTerms(TREASURY, oldHash);
        vm.warp(CREATED + 1 days - 1);
        vm.chainId(31338);
        require(vault.termsHash() == oldHash, "creation domain drifted");
        vm.recordLogs();
        reviseBindings(initialBindings());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 nextHash = vault.termsHash();
        require(logs.length == 1 && logs[0].topics[0] == keccak256("TermsPublished(uint256,bytes32)"), "revision event");
        require(logs[0].topics[1] == bytes32(uint256(2)) && logs[0].topics[2] == nextHash, "published commitment");
        AgreementVault.Terms memory t = vault.currentTerms();
        require(t.vault == address(vault) && t.agreementId == ID && t.chainId == 31337, "domain");
        require(t.treasury == TREASURY && t.manager == MANAGER, "controllers");
        require(t.createdAt == CREATED && t.activationCutoff == CREATED + 1 days, "deadline moved");
        require(nextHash != oldHash, "no-op edit reused hash");
        assertConsentState(2, 0, 0, AgreementVault.State.Draft);
        acceptTerms(TREASURY, nextHash);
        acceptTerms(MANAGER, nextHash);
        assertConsentState(2, 2, 2, AgreementVault.State.Accepted);
    }

    /// @notice Try fresh and repeated decisions at cutoff and require the consent window to be closed.
    function testCutoffClosesBothEntryPointsEvenForPreviouslyAcceptingCaller() public {
        bytes32 h = vault.termsHash();
        acceptTerms(TREASURY, h);
        for (uint256 i; i < 2; ++i) {
            vm.warp(CREATED + 1 days + i);
            vm.expectRevert(AgreementVault.CutoffReached.selector);
            acceptTerms(MANAGER, h);
            vm.expectRevert(AgreementVault.CutoffReached.selector);
            acceptTerms(TREASURY, h);
            vm.expectRevert(AgreementVault.CutoffReached.selector);
            reviseBindings(initialBindings());
            assertConsentState(1, 1, 0, AgreementVault.State.Draft);
        }
    }

    /// @notice Construct agreements with missing or conflicting parties and require validation to reject them.
    function testInvalidAgreementOrParties() public {
        AgreementVault.Bindings memory b = initialBindings();
        vm.expectRevert(AgreementVault.MissingAgreementId.selector);
        createVault(bytes32(0), MANAGER, b);
        vm.expectRevert(AgreementVault.MissingAddress.selector);
        createVault(ID, address(0), b);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.ConflictingIdentity.selector, TREASURY));
        createVault(ID, TREASURY, b);
    }

    /// @notice Try invalid binding revisions after consent and check that accepted terms survive.
    function testInvalidBindingsCannotReplaceAcceptedTerms() public {
        bytes32 h = vault.termsHash();
        acceptTerms(TREASURY, h);
        acceptTerms(MANAGER, h);
        AgreementVault.Bindings memory b = initialBindings();
        b.token0 = b.token1;
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.ConflictingIdentity.selector, b.token1));
        reviseBindings(b);
        b.token0 = address(0x5001);
        vm.expectRevert(AgreementVault.UnsortedCurrencies.selector);
        reviseBindings(b);
        b = initialBindings();
        b.escrow = address(vault);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.ConflictingIdentity.selector, address(vault)));
        reviseBindings(b);
        b = initialBindings();
        b.poolManager = address(0);
        vm.expectRevert(AgreementVault.MissingAddress.selector);
        reviseBindings(b);
        b = initialBindings();
        b.referenceSource = address(0);
        vm.expectRevert(AgreementVault.MissingAddress.selector);
        reviseBindings(b);
        b = initialBindings();
        b.referenceAdapter = address(0);
        vm.expectRevert(AgreementVault.MissingAddress.selector);
        reviseBindings(b);
        require(vault.termsHash() == h, "failed revision changed terms");
        assertConsentState(1, 1, 1, AgreementVault.State.Accepted);
    }
}
