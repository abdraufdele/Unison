// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {ConsentFixture} from "../fixtures/ConsentFixture.sol";

contract ConsentFuzzTest is ConsentFixture {
    /// @notice Try a supplied nonmatching commitment and require that no approval is recorded.
    function testFuzzWrongHashCannotAddApproval(bytes32 supplied) public {
        bytes32 current = vault.termsHash();
        if (supplied == current) supplied ^= bytes32(uint256(1));
        acceptTerms(MANAGER, current);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, supplied, current));
        acceptTerms(TREASURY, supplied);
        assertConsentState(1, 0, 1, AgreementVault.State.Draft);
    }
}
