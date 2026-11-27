// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {ExactToken} from "../../src/ExactToken.sol";
import {CustodyToken} from "../fixtures/CustodyFixture.sol";
import {ActiveFixture} from "../fixtures/ActiveFixture.sol";

contract CloseoutBoundaryTest is ActiveFixture {
    error ExpiredPositionChanged(uint128 expectedLiquidity, uint128 actualLiquidity);
    error PrincipalReceiptShort(uint256 expectedTreasuryB, uint256 actualTreasuryB);

    /// @notice Try a manager removal exactly at expiry and compare actual core liquidity before and after.
    function testExactExpiryPreservesCorePositionAgainstManagerRemoval() public {
        activateFixture();
        bytes32 id = vault.positionId();
        bytes32 salt = vault.positionSalt();
        vm.warp(10_300);
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        require(vault.recordedStop() == 0);
        vm.prank(MANAGER);
        try vault.remove(id, SEED, bounds) {}
        catch (bytes memory reason) {
            require(keccak256(reason) == keccak256(abi.encodeWithSelector(AgreementVault.InvalidPeriod.selector)));
        }
        uint128 actual = seedRangeLiquidity(address(vault), salt);
        if (actual != SEED) revert ExpiredPositionChanged(SEED, actual);
        require(vault.positionId() == id && vault.lastAdjustment() == 0 && hook.pendingAdd() == 0);
        assertCustodyBalances(0, 0, PRINCIPAL - COST, PRINCIPAL - COST, BUDGET);
    }

    /// @notice Keep the compensation recipient blocked across expiry and compare treasury principal receipts with expected amounts.
    function testExpiredTreasuryReceivesPrincipalWithManagerRouteBlocked() public {
        activateFixture();
        swapToTick(-20);
        vm.warp(10_300);
        require(vault.recordedStop() == 0 && escrow.claimable() == BUDGET);
        b.setFault(address(escrow), MANAGER, CustodyToken.Fault.Revert);
        bytes memory transferError = abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b));
        vm.expectRevert(transferError);
        escrow.claim();
        vault.withdrawIdle();
        try vault.exitLiquidity() {}
        catch (bytes memory reason) {
            // Only the escrow-to-manager B route fails in this fixture. Propagate unrelated failures.
            require(keccak256(reason) == keccak256(transferError), "unexpected exit error");
        }
        vault.withdrawIdle();
        uint256 actual = b.balanceOf(address(this));
        uint256 expected = PRINCIPAL - COST + 498_228_754;
        if (actual != expected) revert PrincipalReceiptShort(expected, actual);
        assertCustodyBalances(2_100_346_049, expected, 0, 0, BUDGET);
        require(vault.positionId() == 0 && vault.recordedStop() == 0 && hook.qualifyingSeconds() == 300);
        b.setFault(address(escrow), MANAGER, CustodyToken.Fault.None);
        require(escrow.claim() == BUDGET && b.balanceOf(MANAGER) == BUDGET);
    }
}
