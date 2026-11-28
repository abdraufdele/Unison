// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementRecord} from "../helpers/AgreementRecord.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AgreementActions is AgreementRecord {
    /// @notice Publish a reviewed reference revision while preserving the deployed pair, core and custodians.
    function revise() external {
        Agreement memory a = action();
        string memory json = vm.readFile(vm.envString("REFERENCE_CONFIG"));
        AgreementVault.Bindings memory b = a.terms.bindings;
        b.referenceAdapter = reviewed(json, "adapter");
        b.referenceSource = reviewed(json, "source");
        checkReference(b);
        vm.broadcast(msg.sender);
        a.vault.revise(b);
    }

    /// @notice Accept the supplied current revision as the one selected party.
    function accept() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.vault.accept(a.hash);
    }

    /// @notice Set exactly one funding allowance for principal A or principal plus budget B.
    function approveFunding(bool tokenOne) external {
        Agreement memory a = action();
        require(
            msg.sender == a.terms.treasury && a.state == AgreementVault.State.Accepted
                && block.timestamp < a.terms.activationCutoff,
            "funding closed or wrong signer"
        );
        IERC20 token = IERC20(tokenOne ? a.terms.bindings.token1 : a.terms.bindings.token0);
        uint256 amount =
            tokenOne ? a.terms.parameters.inventory1 + a.terms.parameters.budget : a.terms.parameters.inventory0;
        require(token.allowance(msg.sender, address(a.vault)) == 0, "existing allowance");
        vm.broadcast(msg.sender);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(IERC20.approve, (address(a.vault), amount)));
        require(ok && (result.length == 0 || abi.decode(result, (bool))), "approval failed");
        require(token.allowance(msg.sender, address(a.vault)) == amount, "inexact allowance");
    }

    /// @notice Transfer the accepted inventory and compensation budget to their respective custodians.
    function fund() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.vault.fund(a.hash);
    }

    /// @notice Recheck the accepted reference, seed bounds and custody and open the single service period.
    function activate() external {
        Agreement memory a = action();
        a.vault.preflightActivation(a.hash);
        vm.broadcast(msg.sender);
        a.vault.activate(a.hash);
    }

    /// @notice Cancel unactivated terms under the vault's cutoff and caller rules.
    function cancel() external {
        Agreement memory a = action();
        vm.broadcast(msg.sender);
        a.vault.cancel();
    }
}
