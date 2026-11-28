// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementRecord} from "../helpers/AgreementRecord.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {IOpeningReferenceAdapter} from "../../src/IOpeningReferenceAdapter.sol";
import {IC1Token} from "../../src/ExactToken.sol";

import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract ReadAgreement is AgreementRecord {
    /// @notice Read terms, consent state, active position, qualification and compensation from the same EVM snapshot.
    function run()
        external
        view
        returns (
            AgreementVault.Terms memory terms,
            AgreementVault.State state,
            bytes32 hash,
            bytes32 position,
            bool qualified,
            uint8 failures,
            uint256 earned,
            uint256 reserved,
            uint256 refundable
        )
    {
        Agreement memory a = agreement();
        (qualified, failures) = a.hook.qualification();
        return (
            a.terms,
            a.state,
            a.hash,
            a.position,
            qualified,
            failures,
            a.escrow.earned(),
            a.escrow.reserved(),
            a.escrow.refundable()
        );
    }

    /// @notice Preview the current opening observation and derived service ticks after consent.
    function previewOpening() external view returns (IOpeningReferenceAdapter.Observation memory, int24, int24) {
        return agreement().vault.previewOpeningReference();
    }

    /// @notice Read the funded vault's actual seed quote and custody checks against reviewed terms.
    function preflightActivation() external view returns (AgreementVault.ActivationPreflight memory) {
        return agreement().vault.preflightActivation(vm.envBytes32("TERMS"));
    }

    /// @notice Verify terminal asset recovery and budget reconciliation, including actual escrow and idle balances.
    function verifySettlement() external view returns (uint256 paid, uint256 refunded, uint256 surplus) {
        Agreement memory a = agreement();
        require(
            a.state == AgreementVault.State.Terminated || a.state == AgreementVault.State.Expired
                || a.state == AgreementVault.State.Cancelled,
            "still open"
        );
        require(a.position == 0 && a.vault.positionLiquidity() == 0, "principal in pool");
        if (a.vault.start() != 0) {
            (uint128 liquidity,,) = StateLibrary.getPositionInfo(
                IPoolManager(a.terms.bindings.poolManager),
                a.vault.positionPoolId(),
                address(a.vault),
                a.vault.positionLower(),
                a.vault.positionUpper(),
                a.vault.positionSalt()
            );
            require(liquidity == 0, "core still holds position");
        }
        require(
            IC1Token(a.terms.bindings.token0).balanceOf(address(a.vault)) == 0
                && IC1Token(a.terms.bindings.token1).balanceOf(address(a.vault)) == 0,
            "idle principal"
        );
        paid = a.escrow.claimed();
        refunded = a.escrow.refunded();
        require(
            paid == a.escrow.earned() && paid + refunded == a.escrow.fundedBudget() && a.escrow.reserved() == 0,
            "outstanding rights"
        );
        surplus = IC1Token(a.terms.bindings.token1).balanceOf(address(a.escrow));
    }
}
