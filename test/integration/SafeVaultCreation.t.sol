// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    SafeCreationFixture,
    Vm,
    Enum,
    AgreementVault,
    MockOpeningReferenceAdapter
} from "../fixtures/SafeCreationFixture.sol";

contract SafeVaultCreationTest is SafeCreationFixture {
    error UnexpectedTreasury(address expected, address actual);

    // Forge JSON decodes object fields in alphabetical order.
    struct ImmutableReference {
        uint256 length;
        uint256 start;
    }

    /// @notice Check the same required beneficiary on both the accepted route and the ordinary-CALL control.
    function verifyTreasury(AgreementVault vault) external view {
        if (vault.treasury() != address(safe)) revert UnexpectedTreasury(address(safe), vault.treasury());
    }

    /// @notice Match every non-immutable runtime byte, as in the existing operator's verifyRuntime check.
    function assertVaultRuntime(AgreementVault vault) private view {
        bytes memory actual = address(vault).code;
        bytes memory template = vm.getDeployedCode(VAULT_ARTIFACT);
        require(actual.length == template.length && actual.length > 0, "runtime length");
        string memory artifact = vm.readFile(vm.getArtifactPathByCode(vm.getCode(VAULT_ARTIFACT)));
        string memory root = ".deployedBytecode.immutableReferences";
        string[] memory keys = vm.parseJsonKeys(artifact, root);
        for (uint256 i; i < keys.length; ++i) {
            ImmutableReference[] memory refs =
                abi.decode(vm.parseJson(artifact, string.concat(root, ".", keys[i])), (ImmutableReference[]));
            for (uint256 j; j < refs.length; ++j) {
                uint256 end = refs[j].start + refs[j].length;
                for (uint256 pos = refs[j].start; pos < end; ++pos) {
                    actual[pos] = template[pos];
                }
            }
        }
        require(keccak256(actual) == keccak256(template), "vault runtime");
        address quote = vm.computeCreateAddress(address(vault), 1);
        require(quote.codehash == keccak256(vm.getDeployedCode("OpeningQuote.sol:OpeningQuote")), "constructor child");
    }

    /// @notice Check domain, parties, fixed recipients, committed bindings and all draft rights on the created address.
    function assertDraft(AgreementVault vault, AgreementVault.Bindings memory bindings, uint256 revision) private view {
        AgreementVault.Terms memory terms = vault.currentTerms();
        require(terms.chainId == block.chainid && terms.agreementId == ID && terms.vault == address(vault), "domain");
        require(terms.createdAt == block.timestamp && terms.activationCutoff == block.timestamp + 1 days, "cutoff");
        require(terms.treasury == address(safe) && terms.treasuryRecipient == address(safe), "treasury rights");
        require(terms.manager == manager && terms.managerRecipient == manager, "manager rights");
        require(keccak256(abi.encode(terms.bindings)) == keccak256(abi.encode(bindings)), "draft bindings");
        require(terms.revision == revision && vault.state() == AgreementVault.State.Draft, "draft revision");
        require(vault.treasuryAcceptedRevision() == 0 && vault.managerAcceptedRevision() == 0, "unexpected consent");
        require(vault.fundedPrincipal0() == 0 && vault.fundedPrincipal1() == 0, "unexpected funding");
        require(vault.start() == 0 && vault.scheduledEnd() == 0 && vault.positionId() == 0, "unexpected activation");
    }

    /// @notice Require a threshold-authorized vault with verified runtime, beneficiary and unfunded revision one.
    function createOwnedVault(uint256 first, uint256 second) private returns (AgreementVault vault) {
        vault = createWithPair(first, second, Enum.Operation.DelegateCall);
        this.verifyTreasury(vault);
        assertVaultRuntime(vault);
        assertDraft(vault, draft, 1);
    }

    /// @notice Owners A and B authorize the Safe-context creation.
    function testOwnersABCreateTreasuryVault() public {
        createOwnedVault(0, 1);
    }

    /// @notice Owners A and C authorize the same creation on a fresh proxy.
    function testOwnersACCreateTreasuryVault() public {
        createOwnedVault(0, 2);
    }

    /// @notice Owners B and C authorize the same creation on a fresh proxy.
    function testOwnersBCCreateTreasuryVault() public {
        createOwnedVault(1, 2);
    }

    /// @notice Require the exact Safe signature rejection and preserve both nonce domains and the unused address.
    function rejectCreation(Request memory request, bytes memory signatures, string memory reason) private {
        uint256 nonce = safe.nonce();
        uint64 createNonce = vm.getNonce(address(safe));
        address candidate = vm.computeCreateAddress(address(safe), createNonce);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", reason));
        execute(request, signatures);
        require(safe.nonce() == nonce && vm.getNonce(address(safe)) == createNonce, "rejected nonce change");
        require(candidate.code.length == 0, "unexpected creation");
    }

    /// @notice One genuine owner signature cannot meet threshold two.
    function testSingleSignatureRejected() public {
        Request memory request = creationRequest(Enum.Operation.DelegateCall);
        rejectCreation(request, signature(owners[0], digest(request)), "GS020");
    }

    /// @notice Two copies of a genuine signature cannot count twice.
    function testDuplicateSignatureRejected() public {
        Request memory request = creationRequest(Enum.Operation.DelegateCall);
        rejectCreation(request, signedPair(digest(request), owners[0], owners[0]), "GS026");
    }

    /// @notice An outsider's correctly ordered signature cannot replace a Safe owner.
    function testUnauthorizedSignatureRejected() public {
        Request memory request = creationRequest(Enum.Operation.DelegateCall);
        Vm.Wallet memory outsider = vm.createWallet("local non-owner signer");
        require(!safe.isOwner(outsider.addr), "outsider");
        rejectCreation(request, signedPair(digest(request), owners[0], outsider), "GS026");
    }

    /// @notice Resubmitting the exact old payload and signatures cannot create another child or revise the first.
    function testExecutedCreationCannotReplay() public {
        Request memory request = creationRequest(Enum.Operation.DelegateCall);
        bytes memory signatures = signedPair(digest(request), owners[0], owners[1]);
        AgreementVault vault = createOwnedVault(0, 1);
        bytes32 beforeHash = vault.termsHash();
        rejectCreation(request, signatures, "GS026");
        require(vault.termsHash() == beforeHash, "replayed terms");
        assertDraft(vault, draft, 1);
    }

    /// @notice Identical valid revision calldata fails directly from each actor and succeeds in one signed Safe CALL.
    function testOnlySafeCanReviseDraft() public {
        AgreementVault vault = createOwnedVault(0, 1);
        AgreementVault.Bindings memory next = draft;
        next.referenceAdapter = address(new MockOpeningReferenceAdapter());
        next.referenceSource = next.referenceAdapter;
        bytes32 original = vault.termsHash();
        address[6] memory denied = [owners[0].addr, owners[1].addr, owners[2].addr, manager, executor, address(helper)];
        for (uint256 i; i < denied.length; ++i) {
            vm.prank(denied[i]);
            vm.expectRevert(AgreementVault.NotTreasury.selector);
            vault.revise(next);
            require(vault.termsHash() == original && safe.nonce() == 1, "rejected revision changed state");
            assertDraft(vault, draft, 1);
        }
        Request memory request =
            Request(address(vault), abi.encodeCall(vault.revise, (next)), Enum.Operation.Call, safe.nonce());
        bytes32 hash = digest(request);
        bytes memory signatures = signedPair(hash, owners[1], owners[2]);
        vm.recordLogs();
        require(execute(request, signatures), "inner revision failed");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertSuccess(logs, hash);
        assertPublication(logs, vault, 2);
        require(vault.termsHash() != original && safe.nonce() == 2, "authorized revision");
        assertDraft(vault, next, 2);
    }

    /// @notice Ordinary CALL can succeed for the signers while its helper-owned vault fails ownership verification.
    function testOrdinaryCallRejectsHelperOwnedVault() public {
        uint64 safeCreateNonce = vm.getNonce(address(safe));
        AgreementVault vault = createWithPair(0, 1, Enum.Operation.Call);
        require(vault.treasury() == address(helper) && vm.getNonce(address(safe)) == safeCreateNonce, "helper context");
        vm.expectRevert(abi.encodeWithSelector(UnexpectedTreasury.selector, address(safe), address(helper)));
        this.verifyTreasury(vault);
    }
}
