// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {Vm} from "../helpers/Vm.sol";

abstract contract ConsentFixture {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant TREASURY = address(0x1111);
    address internal constant MANAGER = address(0x2222);
    bytes32 internal constant ID = bytes32(uint256(1));
    uint256 internal constant CREATED = 1000;
    AgreementVault internal vault;

    /// @notice Create the initial vault and actors shared by this suite before each test.
    function setUp() public {
        vm.chainId(31337);
        vm.warp(CREATED);
        vm.setNonce(TREASURY, 1);
        vault = createVault(ID, MANAGER, initialBindings());
    }

    /// @notice Construct the agreement as its intended treasury with the supplied parties and bindings.
    function createVault(bytes32 id, address manager, AgreementVault.Bindings memory b)
        internal
        returns (AgreementVault)
    {
        vm.prank(TREASURY);
        return new AgreementVault(id, manager, b);
    }

    /// @notice Supply distinct, ordered C1 identities for the acceptance-only fixture.
    function initialBindings() internal pure returns (AgreementVault.Bindings memory) {
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

    /// @notice Record the selected fixture parties' decisions against the vault's current proposal.
    function acceptTerms(address caller, bytes32 expected) internal {
        vm.prank(caller);
        vault.accept(expected);
    }

    /// @notice Compare revision, both independent consent records and the effective state.
    function assertConsentState(uint256 rev, uint256 treasuryRecord, uint256 managerRecord, AgreementVault.State status)
        internal
        view
    {
        require(vault.revision() == rev, "revision");
        require(vault.treasuryAcceptedRevision() == treasuryRecord, "treasury decision");
        require(vault.managerAcceptedRevision() == managerRecord, "manager decision");
        require(vault.state() == status, "state");
    }
}
