// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {ClockFixture} from "../fixtures/ClockFixture.sol";

/// @dev Owns the treasury in the real-core fixture. Only the four selected actions are fuzz targets.
contract ServiceHandler is ClockFixture {
    uint256 private paid;
    uint256 private returnedBudget;

    /// @notice Create and activate a fresh agreement before Foundry chooses any actions.
    function openAgreement() external {
        setUp();
        activateFixture();
    }

    /// @notice Move one to twenty seconds forward, booking the old core qualification before the warp.
    function advanceTime(uint8 elapsed) external {
        advanceClockModel(block.timestamp + 1 + elapsed % 20);
        checkpointAndCompare();
    }

    /// @notice Respect cooldown, retire or reopen the seed as manager, and reject a removal once expired.
    function adjustLiquidity() external {
        advanceClockModel(block.timestamp + 30);
        if (block.timestamp >= vault.scheduledEnd()) {
            bytes32 id = vault.positionId();
            AgreementVault.Bounds memory bounds = adjustmentBounds();
            vm.expectRevert(AgreementVault.InvalidPeriod.selector);
            vm.prank(MANAGER);
            vault.remove(id, 1, bounds);
        } else if (vault.positionLiquidity() == 0) {
            addAsManager(SEED);
        } else {
            bytes32 retired = vault.positionSalt();
            removeAsManager(SEED);
            require(seedRangeLiquidity(address(vault), retired) == 0, "retired liquidity");
        }
    }

    /// @notice Pull cumulative pay as a third party and reconcile the fixed recipients at effective expiry.
    function settleBudget() external {
        uint256 due = BUDGET * expected / 300 - paid;
        vm.prank(DONOR);
        require(escrow.claim() == due, "claim receipt");
        paid += due;
        if (block.timestamp >= vault.scheduledEnd()) {
            uint256 remainder = BUDGET - paid - returnedBudget;
            vm.prank(DONOR);
            require(escrow.refund() == remainder, "refund receipt");
            returnedBudget += remainder;
        }
    }

    /// @notice Exercise the caller guard and compare identity and liquidity across the expected rejection.
    function challengeCaller() external {
        bytes32 id = vault.positionId();
        uint128 liquidity = vault.positionLiquidity();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.expectRevert(AgreementVault.NotManager.selector);
        vm.prank(DONOR);
        vault.remove(id, 1, bounds);
        require(vault.positionId() == id && vault.positionLiquidity() == liquidity, "failed removal changed position");
    }

    /// @notice Compare projected service, reserve and actual token receipts with independent interval accounting.
    function assertRights() external view {
        assertClockProjection();
        uint256 earned = BUDGET * expected / 300;
        require(expected <= 300 && paid <= earned && earned + returnedBudget <= BUDGET);
        require(escrow.earned() == earned && escrow.reserved() == earned - paid);
        require(b.balanceOf(address(escrow)) == BUDGET - paid - returnedBudget);
        require(b.balanceOf(MANAGER) == paid && b.balanceOf(address(this)) == returnedBudget);
    }
}

contract ServiceAccountingInvariantTest {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    ServiceHandler private handler;

    /// @notice Initialize one handler-owned treasury, named manager and unrelated caller per sequence.
    function setUp() public {
        handler = new ServiceHandler();
        handler.openAgreement();
    }

    /// @notice Restrict Foundry to the handler so random calls cannot mint tokens or modify fixture wiring.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// @notice Select four accounting actions, excluding setup and read-only assertion entry points.
    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.advanceTime.selector;
        selectors[1] = handler.adjustLiquidity.selector;
        selectors[2] = handler.settleBudget.selector;
        selectors[3] = handler.challengeCaller.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// @notice After every action, check earned and unpaid rights against modeled intervals and actual custody.
    function invariantServiceAndFundedRightsReconcile() public view {
        handler.assertRights();
    }
}
