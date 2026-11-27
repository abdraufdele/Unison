// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../src/AgreementVault.sol";
import {CompensationEscrow} from "../src/CompensationEscrow.sol";
import {IOpeningReferenceAdapter} from "../src/IOpeningReferenceAdapter.sol";
import {ServiceHook} from "../src/ServiceHook.sol";
import {ScriptEnvironment} from "./CreateVault.s.sol";

interface RehearsalEnvironment is ScriptEnvironment {
    /// @notice Group successive simulated transactions under the indicated account.
    function startBroadcast(address actor) external;

    /// @notice End the group before switching from treasury to manager or returning to the verifier.
    function stopBroadcast() external;
}

interface FixtureToken {
    /// @notice Grant only the exact funding allowance for this fixture vault.
    function approve(address spender, uint256 baseUnits) external returns (bool);

    /// @notice Read the actual asset receipt in token base units.
    function balanceOf(address holder) external view returns (uint256);
}

interface FixtureOpening {
    /// @notice Publish the current mock parity observation before simulating activation.
    function publish(IOpeningReferenceAdapter.Observation calldata observed) external;
}

/// @notice Simulate a draft C1 purchase and independent closeout on local or Sepolia mock assets.
contract RehearseAgreementScript {
    RehearsalEnvironment private constant vm =
        RehearsalEnvironment(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Verify actual core seed ownership, fixed recipients and return of principal at immediate close.
    function run() external {
        require(block.chainid == vm.envUint("UNISON_CHAIN_ID") && (block.chainid == 31337 || block.chainid == 1301));
        AgreementVault v = AgreementVault(vm.envAddress("UNISON_VAULT"));
        AgreementVault.Terms memory t = v.currentTerms();
        bytes32 hash = v.termsHash();
        require(t.agreementId == abi.decode(vm.envBytes("UNISON_RUN_ID"), (bytes32)));
        require(hash == abi.decode(vm.envBytes("UNISON_TERMS"), (bytes32)) && v.state() == AgreementVault.State.Draft);
        require(t.chainId == block.chainid && t.treasury == t.treasuryRecipient && t.manager == t.managerRecipient);
        if (block.chainid == 1301) require(t.bindings.poolManager == 0x00B036B58a818B1BC34d502D3fE730Db729e62AC);
        FixtureToken a = FixtureToken(t.bindings.token0);
        FixtureToken b = FixtureToken(t.bindings.token1);
        CompensationEscrow escrow = CompensationEscrow(t.bindings.escrow);
        vm.broadcast(t.manager);
        v.accept(hash);
        vm.startBroadcast(t.treasury);
        v.accept(hash);
        require(a.approve(address(v), t.parameters.inventory0));
        require(b.approve(address(v), t.parameters.inventory1 + t.parameters.budget));
        v.fund(hash);
        FixtureOpening(t.bindings.referenceAdapter)
            .publish(
                IOpeningReferenceAdapter.Observation(
                    t.bindings.referenceSource,
                    t.bindings.token0,
                    t.bindings.token1,
                    6,
                    6,
                    8,
                    1e8,
                    block.timestamp,
                    true
                )
            );
        v.activate(hash);
        require(v.positionLiquidity() == t.parameters.seedLiquidity && v.positionId() != bytes32(0));
        require(ServiceHook(t.bindings.hook).positionId() == v.positionId());
        v.terminate();
        v.exitLiquidity();
        v.withdrawIdle();
        require(v.positionLiquidity() == 0 && a.balanceOf(address(v)) == 0 && b.balanceOf(address(v)) == 0);
        require(a.balanceOf(t.treasuryRecipient) > 0 && b.balanceOf(t.treasuryRecipient) > 0);
        escrow.refund();
        escrow.claim();
        vm.stopBroadcast();
        require(escrow.claimed() + escrow.refunded() == t.parameters.budget && escrow.reserved() == 0);
    }
}
