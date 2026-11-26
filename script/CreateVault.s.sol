// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../src/AgreementVault.sol";
import {IC1Token} from "../src/ExactToken.sol";

interface ScriptEnvironment {
    /// @notice Read the operator's expected network ID for this simulation.
    function envUint(string calldata name) external view returns (uint256);

    /// @notice Read the intended treasury account for the direct contract creation.
    function envAddress(string calldata name) external view returns (address);

    /// @notice Read the ABI-encoded vault constructor arguments produced by deployment preparation.
    function envBytes(string calldata name) external view returns (bytes memory);

    /// @notice Load creation bytecode from the named compiled Forge artifact.
    function getCode(string calldata artifactPath) external view returns (bytes memory);

    /// @notice Attribute the next CREATE to the intended signer in the Foundry transaction plan.
    function broadcast(address signer) external;
}

/// @notice Foundry rehearsal of the direct treasury CREATE used by the deployment driver.
contract CreateVaultScript {
    ScriptEnvironment private constant vm = ScriptEnvironment(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Simulate the vault constructor as treasury and check its initial domain before the driver submits it.
    /// @return deployed Actual address returned by CREATE during this execution.
    function run() external returns (address deployed) {
        require(block.chainid == vm.envUint("UNISON_CHAIN_ID"), "wrong chain");
        require(block.chainid == 31337 || block.chainid == 1301, "C1 mock deployment network");
        address treasury = vm.envAddress("UNISON_TREASURY");
        bytes memory arguments = vm.envBytes("UNISON_VAULT_ARGS");
        (bytes32 id, address manager, AgreementVault.Bindings memory b) =
            abi.decode(arguments, (bytes32, address, AgreementVault.Bindings));
        require(treasury != address(0) && treasury != manager && id != 0, "invalid parties or id");
        require(b.poolManager.code.length > 0 && b.referenceAdapter.code.length > 0, "missing dependency");
        if (block.chainid == 1301) require(b.poolManager == 0x00B036B58a818B1BC34d502D3fE730Db729e62AC, "wrong core");
        require(IC1Token(b.token0).decimals() == 6 && IC1Token(b.token1).decimals() == 6 && b.token0 < b.token1);
        bytes memory init = bytes.concat(vm.getCode("AgreementVault.sol:AgreementVault"), arguments);
        vm.broadcast(treasury);
        assembly ("memory-safe") {
            deployed := create(0, add(init, 32), mload(init))
        }
        require(deployed != address(0), "vault CREATE failed");
        AgreementVault vault = AgreementVault(deployed);
        require(vault.treasury() == treasury && vault.manager() == manager && vault.agreementId() == id);
        require(vault.creationChainId() == block.chainid && vault.state() == AgreementVault.State.Draft);
    }
}
