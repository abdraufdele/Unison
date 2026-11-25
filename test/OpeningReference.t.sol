// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../src/AgreementVault.sol";
import {IOpeningReferenceAdapter} from "../src/IOpeningReferenceAdapter.sol";
import {OpeningBand} from "../src/OpeningBand.sol";
import {CustodyFixture} from "./fixtures/CustodyFixture.sol";
import {MockOpeningReferenceAdapter} from "./fixtures/MockOpeningReferenceAdapter.sol";

interface VmReference {
    function mockCall(address callee, bytes calldata data, bytes calldata result) external;
    function mockCallRevert(address callee, bytes calldata data, bytes calldata reason) external;
    function expectCall(address callee, bytes calldata data, uint64 count) external;
    function expectRevert() external;
}

contract OpeningReferenceTest is CustodyFixture {
    VmReference private constant referenceVm = VmReference(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant NOW = 10_000;
    address private constant SOURCE = address(0xc100);
    MockOpeningReferenceAdapter private adapter;

    function _configure() private returns (IOpeningReferenceAdapter.Observation memory sample) {
        vm.warp(NOW);
        adapter = new MockOpeningReferenceAdapter();
        AgreementVault.Bindings memory bindings = vault.currentTerms().bindings;
        bindings.referenceAdapter = address(adapter);
        bindings.referenceSource = SOURCE;
        vault.revise(bindings);
        sample = IOpeningReferenceAdapter.Observation(SOURCE, address(a), address(b), 6, 6, 8, 100_000_000, NOW, true);
        adapter.publish(sample);
    }

    function testAcceptedAndFundedPreviewReadsCurrentAdapterOncePerCall() public {
        IOpeningReferenceAdapter.Observation memory sample = _configure();
        vm.expectRevert(AgreementVault.NotAccepted.selector);
        vault.previewOpeningReference();
        _accept();
        referenceVm.expectCall(address(adapter), abi.encodeCall(adapter.observation, ()), 2);
        (IOpeningReferenceAdapter.Observation memory actual, int24 lo, int24 hi) = vault.previewOpeningReference();
        require(keccak256(abi.encode(actual)) == keccak256(abi.encode(sample)), "observation");
        require(lo == -120 && hi == 120 && vault.state() == AgreementVault.State.Accepted, "parity");
        bytes32 h = vault.termsHash();
        vault.fund(h);
        sample.answer = 125_000_000;
        adapter.publish(sample);
        (, lo, hi) = vault.previewOpeningReference();
        require(lo == 2100 && hi == 2340 && vault.state() == AgreementVault.State.Funded, "funded preview");
        require(vault.termsHash() == h && escrow.refundable() == 0, "agreement changed");
    }

    function testRevisionRequiresBothNewApprovalsAndUsesNewSource() public {
        _configure();
        _accept();
        AgreementVault.Bindings memory bindings = vault.currentTerms().bindings;
        bindings.referenceSource = address(0xc101);
        vault.revise(bindings);
        vault.accept(vault.termsHash());
        vm.expectRevert(AgreementVault.NotAccepted.selector);
        vault.previewOpeningReference();
        _accept();
        vm.expectRevert(AgreementVault.ReferenceMismatch.selector);
        vault.previewOpeningReference();
    }

    function testFreshnessBoundaries() public {
        IOpeningReferenceAdapter.Observation memory sample = _configure();
        _accept();
        for (uint256 age = 59; age <= 61; ++age) {
            sample.updatedAt = NOW - age;
            adapter.publish(sample);
            if (age == 61) vm.expectRevert(AgreementVault.InvalidObservation.selector);
            vault.previewOpeningReference();
        }
    }

    function testRejectsInvalidAnswerTimeAndCompletion() public {
        IOpeningReferenceAdapter.Observation memory sample = _configure();
        _accept();
        sample.answer = 0;
        _reject(sample, AgreementVault.InvalidObservation.selector);
        sample.answer = -1;
        _reject(sample, AgreementVault.InvalidObservation.selector);
        sample.answer = type(int256).max;
        _reject(sample, OpeningBand.UnrepresentablePrice.selector);
        sample.answer = 100_000_000;
        sample.updatedAt = 0;
        _reject(sample, AgreementVault.InvalidObservation.selector);
        sample.updatedAt = NOW + 1;
        _reject(sample, AgreementVault.InvalidObservation.selector);
        sample.updatedAt = NOW;
        sample.complete = false;
        _reject(sample, AgreementVault.InvalidObservation.selector);
    }

    function testRejectsWrongSourcePairOrientationAndDenominations() public {
        IOpeningReferenceAdapter.Observation memory sample = _configure();
        _accept();
        sample.source = address(7);
        _reject(sample, AgreementVault.ReferenceMismatch.selector);
        sample.source = SOURCE;
        sample.base = address(7);
        _reject(sample, AgreementVault.ReferenceMismatch.selector);
        sample.base = address(a);
        sample.quote = address(7);
        _reject(sample, AgreementVault.ReferenceMismatch.selector);
        sample.base = address(b);
        sample.quote = address(a);
        _reject(sample, AgreementVault.ReferenceMismatch.selector);
        sample.base = address(a);
        sample.quote = address(b);
        sample.baseDecimals = 18;
        _reject(sample, AgreementVault.ReferenceMismatch.selector);
        sample.baseDecimals = 6;
        sample.quoteDecimals = 18;
        _reject(sample, AgreementVault.ReferenceMismatch.selector);
        sample.quoteDecimals = 6;
        sample.feedDecimals = 6;
        _reject(sample, AgreementVault.ReferenceMismatch.selector);
    }

    function testReadsTokenDecimalsFromBothActualContracts() public {
        _configure();
        _accept();
        a.setDecimals(9);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.InvalidDecimals.selector, address(a)));
        vault.previewOpeningReference();
        a.setDecimals(6);
        b.setDecimals(9);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.InvalidDecimals.selector, address(b)));
        vault.previewOpeningReference();
    }

    function testRejectsRevertingTruncatedTrailingAndNoncanonicalAdapterData() public {
        IOpeningReferenceAdapter.Observation memory sample = _configure();
        _accept();
        bytes memory query = abi.encodeCall(adapter.observation, ());
        referenceVm.mockCallRevert(address(adapter), query, hex"abcd");
        vm.expectRevert(AgreementVault.UnreadableReference.selector);
        vault.previewOpeningReference();
        referenceVm.mockCall(address(adapter), query, hex"01");
        vm.expectRevert(AgreementVault.UnreadableReference.selector);
        vault.previewOpeningReference();
        referenceVm.mockCall(address(adapter), query, bytes.concat(abi.encode(sample), hex"00"));
        vm.expectRevert(AgreementVault.UnreadableReference.selector);
        vault.previewOpeningReference();
        bytes memory invalidBool = abi.encode(sample);
        invalidBool[invalidBool.length - 1] = 0x02;
        referenceVm.mockCall(address(adapter), query, invalidBool);
        referenceVm.expectRevert();
        vault.previewOpeningReference();
    }

    function _reject(IOpeningReferenceAdapter.Observation memory sample, bytes4 reason) private {
        adapter.publish(sample);
        vm.expectRevert(reason);
        vault.previewOpeningReference();
    }
}
