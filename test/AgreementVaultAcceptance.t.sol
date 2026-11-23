// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../src/AgreementVault.sol";

// Test-only Foundry cheatcodes. All state assertions use the vault's public interface.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function warp(uint256 timestamp) external;
    function chainId(uint256 id) external;
    function setNonce(address account, uint64 nonce) external;
    function prank(address caller) external;
    function expectRevert(bytes calldata reason) external;
    function expectRevert(bytes4 selector) external;
    function snapshotState() external returns (uint256);
    function revertToStateAndDelete(uint256 snapshot) external returns (bool);
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

contract AgreementVaultAcceptanceTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant TREASURY = address(0x1111);
    address private constant MANAGER = address(0x2222);
    bytes32 private constant ID = bytes32(uint256(1));
    uint256 private constant CREATED = 1000;
    AgreementVault private vault;

    function setUp() public {
        vm.chainId(31337);
        vm.warp(CREATED);
        vm.setNonce(TREASURY, 1);
        vault = _create(ID, MANAGER, _bindings());
    }

    function _bindings() private pure returns (AgreementVault.Bindings memory) {
        return AgreementVault.Bindings({
            poolManager: address(0x3000),
            token0: address(0x4000),
            token1: address(0x5000),
            hook: address(0x6000),
            escrow: address(0x7000),
            referenceAdapter: address(0x8000),
            referenceSource: address(0x9000)
        });
    }

    function _create(bytes32 id, address manager, AgreementVault.Bindings memory b) private returns (AgreementVault) {
        vm.prank(TREASURY);
        return new AgreementVault(id, manager, b);
    }

    function _accept(address caller, bytes32 expected) private {
        vm.prank(caller);
        vault.accept(expected);
    }

    function _revise(AgreementVault.Bindings memory b) private {
        vm.prank(TREASURY);
        vault.revise(b);
    }

    function _expectState(uint256 rev, uint256 treasuryRecord, uint256 managerRecord, AgreementVault.State status)
        private
        view
    {
        require(vault.revision() == rev, "revision");
        require(vault.treasuryAcceptedRevision() == treasuryRecord, "treasury decision");
        require(vault.managerAcceptedRevision() == managerRecord, "manager decision");
        require(vault.state() == status, "state");
    }

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
        _expectState(1, 0, 0, AgreementVault.State.Draft);
    }

    function testTreasuryFirstAndRepeatedAcceptance() public {
        bytes32 h = vault.termsHash();
        vm.recordLogs();
        _accept(TREASURY, h);
        _expectState(1, 1, 0, AgreementVault.State.Draft);
        _accept(TREASURY, h);
        _accept(MANAGER, h);
        _accept(MANAGER, h);
        _expectState(1, 1, 1, AgreementVault.State.Accepted);
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

    function testManagerFirst() public {
        bytes32 h = vault.termsHash();
        _accept(MANAGER, h);
        _expectState(1, 0, 1, AgreementVault.State.Draft);
        _accept(TREASURY, h);
        _expectState(1, 1, 1, AgreementVault.State.Accepted);
    }

    function testUnauthorizedAcceptanceAndRevision() public {
        bytes32 h = vault.termsHash();
        vm.expectRevert(AgreementVault.NotParty.selector);
        vault.accept(h);
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vault.revise(_bindings());
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(MANAGER);
        vault.revise(_bindings());
        _expectState(1, 0, 0, AgreementVault.State.Draft);
        require(vault.termsHash() == h, "unauthorized call changed terms");
    }

    function testFuzzWrongHashCannotAddApproval(bytes32 supplied) public {
        bytes32 current = vault.termsHash();
        if (supplied == current) supplied ^= bytes32(uint256(1));
        _accept(MANAGER, current);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, supplied, current));
        _accept(TREASURY, supplied);
        _expectState(1, 0, 1, AgreementVault.State.Draft);
    }

    function testOtherVaultHashRejectedEvenWithSamePartiesIdTimeAndTerms() public {
        AgreementVault other = _create(ID, MANAGER, _bindings());
        bytes32 foreign = other.termsHash();
        bytes32 current = vault.termsHash();
        require(foreign != current, "domain collision");
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, foreign, current));
        _accept(TREASURY, foreign);
        _expectState(1, 0, 0, AgreementVault.State.Draft);
    }

    function testRevisionClearsBothAndRestoringTermsRequiresFreshDecisions() public {
        bytes32 first = vault.termsHash();
        _accept(TREASURY, first);
        _accept(MANAGER, first);
        AgreementVault.Bindings memory updated = _bindings();
        updated.hook = address(0x6001);
        _revise(updated);
        _expectState(2, 0, 0, AgreementVault.State.Draft);
        bytes32 second = vault.termsHash();
        require(vault.currentTerms().bindings.hook == updated.hook, "revised hook not exposed");
        _accept(MANAGER, second);
        _revise(_bindings());
        bytes32 third = vault.termsHash();
        require(third != first && third != second, "reused commitment");
        _expectState(3, 0, 0, AgreementVault.State.Draft);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, first, third));
        _accept(TREASURY, first);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, second, third));
        _accept(MANAGER, second);
        _accept(MANAGER, third);
        _expectState(3, 0, 3, AgreementVault.State.Draft);
        _accept(TREASURY, third);
        _expectState(3, 3, 3, AgreementVault.State.Accepted);
    }

    // Compare alternative revision-two proposals on the SAME instance at the SAME timestamp.
    function _revisionTwoHash(AgreementVault.Bindings memory next) private returns (bytes32) {
        uint256 snapshot = vm.snapshotState();
        _revise(next);
        bytes32 h = vault.termsHash();
        require(vm.revertToStateAndDelete(snapshot), "snapshot restore");
        return h;
    }

    function testEachRevisableFieldAffectsCommitmentAtSameRevision() public {
        AgreementVault.Bindings memory b = _bindings();
        bytes32 base = _revisionTwoHash(b);
        b.poolManager = address(0x3001);
        require(_revisionTwoHash(b) != base, "pool manager omitted");
        b = _bindings();
        b.token0 = address(0x4001);
        require(_revisionTwoHash(b) != base, "token0 omitted");
        b = _bindings();
        b.token1 = address(0x5001);
        require(_revisionTwoHash(b) != base, "token1 omitted");
        b = _bindings();
        b.hook = address(0x6001);
        require(_revisionTwoHash(b) != base, "hook omitted");
        b = _bindings();
        b.escrow = address(0x7001);
        require(_revisionTwoHash(b) != base, "escrow omitted");
        b = _bindings();
        b.referenceAdapter = address(0x8001);
        require(_revisionTwoHash(b) != base, "adapter omitted");
        b = _bindings();
        b.referenceSource = address(0x9001);
        require(_revisionTwoHash(b) != base, "source omitted");
    }

    function testNoOpRevisionAtLastSecondKeepsControllerDomainAndDeadline() public {
        bytes32 oldHash = vault.termsHash();
        _accept(TREASURY, oldHash);
        vm.warp(CREATED + 1 days - 1);
        vm.chainId(31338);
        require(vault.termsHash() == oldHash, "creation domain drifted");
        vm.recordLogs();
        _revise(_bindings());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 nextHash = vault.termsHash();
        require(logs.length == 1 && logs[0].topics[0] == keccak256("TermsPublished(uint256,bytes32)"), "revision event");
        require(logs[0].topics[1] == bytes32(uint256(2)) && logs[0].topics[2] == nextHash, "published commitment");
        AgreementVault.Terms memory t = vault.currentTerms();
        require(t.vault == address(vault) && t.agreementId == ID && t.chainId == 31337, "domain");
        require(t.treasury == TREASURY && t.manager == MANAGER, "controllers");
        require(t.createdAt == CREATED && t.activationCutoff == CREATED + 1 days, "deadline moved");
        require(nextHash != oldHash, "no-op edit reused hash");
        _expectState(2, 0, 0, AgreementVault.State.Draft);
        _accept(TREASURY, nextHash);
        _accept(MANAGER, nextHash);
        _expectState(2, 2, 2, AgreementVault.State.Accepted);
    }

    function testCutoffClosesBothEntryPointsEvenForPreviouslyAcceptingCaller() public {
        bytes32 h = vault.termsHash();
        _accept(TREASURY, h);
        for (uint256 i; i < 2; ++i) {
            vm.warp(CREATED + 1 days + i);
            vm.expectRevert(AgreementVault.CutoffReached.selector);
            _accept(MANAGER, h);
            vm.expectRevert(AgreementVault.CutoffReached.selector);
            _accept(TREASURY, h);
            vm.expectRevert(AgreementVault.CutoffReached.selector);
            _revise(_bindings());
            _expectState(1, 1, 0, AgreementVault.State.Draft);
        }
    }

    function testInvalidAgreementOrParties() public {
        AgreementVault.Bindings memory b = _bindings();
        vm.expectRevert(AgreementVault.MissingAgreementId.selector);
        _create(bytes32(0), MANAGER, b);
        vm.expectRevert(AgreementVault.MissingAddress.selector);
        _create(ID, address(0), b);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.ConflictingIdentity.selector, TREASURY));
        _create(ID, TREASURY, b);
    }

    function testInvalidBindingsCannotReplaceAcceptedTerms() public {
        bytes32 h = vault.termsHash();
        _accept(TREASURY, h);
        _accept(MANAGER, h);
        AgreementVault.Bindings memory b = _bindings();
        b.token0 = b.token1;
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.ConflictingIdentity.selector, b.token1));
        _revise(b);
        b.token0 = address(0x5001);
        vm.expectRevert(AgreementVault.UnsortedCurrencies.selector);
        _revise(b);
        b = _bindings();
        b.escrow = address(vault);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.ConflictingIdentity.selector, address(vault)));
        _revise(b);
        b = _bindings();
        b.poolManager = address(0);
        vm.expectRevert(AgreementVault.MissingAddress.selector);
        _revise(b);
        b = _bindings();
        b.referenceSource = address(0);
        vm.expectRevert(AgreementVault.MissingAddress.selector);
        _revise(b);
        b = _bindings();
        b.referenceAdapter = address(0);
        vm.expectRevert(AgreementVault.MissingAddress.selector);
        _revise(b);
        require(vault.termsHash() == h, "failed revision changed terms");
        _expectState(1, 1, 1, AgreementVault.State.Accepted);
    }
}
