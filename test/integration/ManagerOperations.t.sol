// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {IOpeningReferenceAdapter} from "../../src/IOpeningReferenceAdapter.sol";
import {CustodyLock} from "../../src/ExactToken.sol";
import {Operation, ServiceHook} from "../../src/ServiceHook.sol";
import {PositionAccountingFixture} from "../fixtures/PositionAccountingFixture.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract ManagerOperationsTest is PositionAccountingFixture {
    using StateLibrary for IPoolManager;

    struct Balances {
        uint256 vaultA;
        uint256 vaultB;
        uint256 coreA;
        uint256 coreB;
    }

    bool private probeAdd;

    /// @notice Run the test's configured probe during a mock token transfer.
    function onTransfer() public override {
        if (!probeAdd) {
            super.onTransfer();
            return;
        }
        require(msg.sender == address(b));
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        // Core has changed L, but vault settlement has not completed. Public checkpointing
        // inside a transfer cannot install that intermediate state or credit extra time.
        require(hook.checkpoint() == 30 && hook.positionId() == id && hook.observedLiquidity() == SEED);
        vm.expectRevert(CustodyLock.ReentrantCall.selector);
        vm.prank(MANAGER);
        vault.add(id, -120, 120, 1, bounds);
        IPoolManager.ModifyLiquidityParams memory leg =
            IPoolManager.ModifyLiquidityParams(-120, 120, 1, bytes32(uint256(1)));
        vm.expectRevert(AgreementVault.InvalidOperation.selector);
        vm.prank(address(core));
        vault.unlockCallback(abi.encode(Operation.Add, leg, PRINCIPAL, PRINCIPAL));
        vm.expectRevert(ServiceHook.InvalidAddContext.selector);
        vm.prank(address(core));
        hook.beforeAddLiquidity(address(vault), key, leg, abi.encode(Operation.Add));
        ++blockedCalls;
    }

    /// @notice Probe the manager entry points during token settlement and check the grant and custody lock.
    function testConsumedGrantsAndManagerLockDuringSettlement() public {
        activateAfterCooldown();
        probeAdd = true;
        b.setProbe(this);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.add(id, -120, 120, 1, bounds);
        require(blockedCalls == 1 && vault.lastAdjustment() == 10_030);
        assertLivePosition(-120, 120, 1, SEED + 1);
    }

    /// @notice Prepare an active position at the fixture's first management opportunity.
    function activateAfterCooldown() private {
        activateFixture();
        vm.warp(10_030);
    }

    /// @notice Read position liquidity at the modeled ticks and salt directly from core.
    function corePositionLiquidity(int24 lower, int24 upper, uint256 salt) private view returns (uint128 l) {
        (l,,) = core.getPositionInfo(key.toId(), address(vault), lower, upper, bytes32(salt));
    }

    /// @notice Reconcile vault and core identity, salt, ticks and actual live liquidity.
    function assertLivePosition(int24 lower, int24 upper, uint256 salt, uint128 l) private view {
        require(
            vault.positionLower() == lower && vault.positionUpper() == upper && vault.positionSalt() == bytes32(salt)
        );
        bytes32 id =
            l == 0 ? bytes32(0) : keccak256(abi.encode(key.toId(), address(vault), lower, upper, bytes32(salt)));
        require(
            vault.positionId() == id && vault.positionLiquidity() == l && corePositionLiquidity(lower, upper, salt) == l
        );
        require(hook.pendingAdd() == 0);
    }

    /// @notice Capture custody and core balances before comparing a manager leg.
    function snapshotBalances() private view returns (Balances memory) {
        return Balances(
            a.balanceOf(address(vault)),
            b.balanceOf(address(vault)),
            a.balanceOf(address(core)),
            b.balanceOf(address(core))
        );
    }

    /// @notice Compare the signed balance changes produced by the completed core operation.
    function assertSettlement(Balances memory beforeOp, int256 deltaA, int256 deltaB) private view {
        Balances memory afterOp = snapshotBalances();
        require(int256(afterOp.vaultA) - int256(beforeOp.vaultA) == deltaA);
        require(int256(afterOp.vaultB) - int256(beforeOp.vaultB) == deltaB);
        require(int256(beforeOp.coreA) - int256(afterOp.coreA) == deltaA);
        require(int256(beforeOp.coreB) - int256(afterOp.coreB) == deltaB);
        require(b.balanceOf(address(escrow)) == BUDGET && escrow.fundedBudget() == BUDGET && escrow.refunded() == 0);
        require(a.balanceOf(MANAGER) == 0 && b.balanceOf(MANAGER) == 0);
    }

    /// @notice Add and partially remove liquidity, then empty and reopen the same ticks under a fresh salt.
    function testAddPartialFullRemoveAndReopenSameTicks() public {
        activateAfterCooldown();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        bytes32 seedId = vault.positionId();
        bounds.maxInput0 = COST;
        bounds.maxInput1 = COST;
        Balances memory beforeOp = snapshotBalances();
        vm.prank(MANAGER);
        vault.add(seedId, -120, 120, SEED, bounds);
        assertSettlement(beforeOp, -int256(COST), -int256(COST));
        assertLivePosition(-120, 120, 1, 2 * SEED);

        vm.warp(10_060);
        bounds = adjustmentBounds();
        (uint256 outA, uint256 outB) = quotePrincipal(-120, 120, 2 * SEED - 1, false);
        beforeOp = snapshotBalances();
        vm.prank(MANAGER);
        vault.remove(seedId, 2 * SEED - 1, bounds);
        assertSettlement(beforeOp, int256(outA), int256(outB));
        assertLivePosition(-120, 120, 1, 1); // Below the agreed minimum, still live and removable.

        vm.warp(10_090);
        bounds = adjustmentBounds();
        beforeOp = snapshotBalances();
        vm.prank(MANAGER);
        vault.remove(seedId, 1, bounds);
        assertSettlement(beforeOp, 0, 0);
        assertLivePosition(-120, 120, 1, 0);

        vm.warp(10_120);
        bounds = adjustmentBounds();
        vm.expectRevert(AgreementVault.PositionMismatch.selector);
        vm.prank(MANAGER);
        vault.add(seedId, -120, 120, SEED, bounds);
        vm.prank(MANAGER);
        vault.add(0, -120, 120, SEED, bounds);
        assertLivePosition(-120, 120, 2, SEED);
        require(corePositionLiquidity(-120, 120, 1) == 0 && vault.lastAdjustment() == 10_120);
        vm.warp(10_150);
        bounds = adjustmentBounds();
        vm.expectRevert(AgreementVault.PositionMismatch.selector);
        vm.prank(MANAGER);
        vault.remove(seedId, SEED, bounds);
    }

    /// @notice Submit stale identities, invalid ranges and disallowed liquidity and require rejection.
    function testRangeLiquidityAndIdentityRejections() public {
        activateAfterCooldown();
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.expectRevert(AgreementVault.PositionMismatch.selector);
        vm.prank(MANAGER);
        vault.add(id, -180, 120, 1, bounds);
        expectRangeRejection(id, -120, 120, bounds); // Same range is not a rerange.
        expectRangeRejection(id, -60, 120, bounds);
        expectRangeRejection(id, -120, 60, bounds);
        expectRangeRejection(id, -121, 120, bounds);
        expectRangeRejection(id, -120, 121, bounds);
        expectRangeRejection(id, -300, 120, bounds);
        expectRangeRejection(id, -120, 300, bounds);
        expectRangeRejection(id, -300, 240, bounds);
        expectRangeRejection(id, 120, -120, bounds);
        expectRangeRejection(id, -887280, 120, bounds);
        vm.expectRevert(AgreementVault.LiquidityLimit.selector);
        vm.prank(MANAGER);
        vault.add(id, -120, 120, SEED + 1, bounds);
        vm.expectRevert(AgreementVault.LiquidityLimit.selector);
        vm.prank(MANAGER);
        vault.add(id, -120, 120, 0, bounds);
        vm.expectRevert(AgreementVault.LiquidityLimit.selector);
        vm.prank(MANAGER);
        vault.remove(id, 0, bounds);
        vm.expectRevert(AgreementVault.LiquidityLimit.selector);
        vm.prank(MANAGER);
        vault.remove(id, SEED + 1, bounds);
        vm.expectRevert(AgreementVault.LiquidityLimit.selector);
        vm.prank(MANAGER);
        vault.rerange(id, -240, 240, 0, bounds);
        vm.expectRevert(AgreementVault.LiquidityLimit.selector);
        vm.prank(MANAGER);
        vault.rerange(id, -240, 240, 2 * SEED + 1, bounds);
        assertLivePosition(-120, 120, 1, SEED);
        require(vault.lastAdjustment() == 0);
        vm.prank(MANAGER);
        vault.rerange(id, -240, 240, SEED, bounds);
        assertLivePosition(-240, 240, 2, SEED);
        require(corePositionLiquidity(-120, 120, 1) == 0 && vault.bandLower() == -120 && vault.bandUpper() == 120);
    }

    /// @notice Keep each edge within extension but exceed total width and require the independent width check.
    function testWidthCapAlsoAppliesWhenBothEdgesAreWithinExtension() public {
        prepareFundedFixture();
        adapter.publish(
            IOpeningReferenceAdapter.Observation(
                address(adapter), address(a), address(b), 6, 6, 8, 101010101, block.timestamp, true
            )
        );
        vault.activate(h);
        require(vault.bandLower() == -60 && vault.bandUpper() == 240);
        vm.warp(10_030);
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        bounds.tickLower = -180;
        bounds.tickUpper = 360;
        bytes32 id = vault.positionId();
        expectRangeRejection(id, -180, 360, bounds);
        vm.prank(MANAGER);
        vault.rerange(id, -180, 300, SEED, bounds);
        assertLivePosition(-180, 300, 2, SEED);
    }

    /// @notice Submit a manager adjustment with the given invalid edges and check rejection.
    function expectRangeRejection(bytes32 id, int24 lower, int24 upper, AgreementVault.Bounds memory bounds) private {
        vm.expectRevert(AgreementVault.InvalidRange.selector);
        vm.prank(MANAGER);
        vault.rerange(id, lower, upper, 1, bounds);
    }

    /// @notice Exercise caller and terms checks and verify proceeds stay with the accepted custodian.
    function testManagerTermsAndRecipientSurface() public {
        activateAfterCooldown();
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.expectRevert(AgreementVault.NotManager.selector);
        vault.add(id, -120, 120, 1, bounds);
        vm.expectRevert(AgreementVault.NotManager.selector);
        vault.remove(id, 1, bounds);
        vm.expectRevert(AgreementVault.NotManager.selector);
        vault.rerange(id, -180, 120, SEED, bounds);
        bounds.termsHash = bytes32(uint256(9));
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, bounds.termsHash, h));
        vm.prank(MANAGER);
        vault.remove(id, SEED, bounds);
        bounds.termsHash = h;
        vm.prank(MANAGER);
        (bool ok,) = address(vault)
            .call(
                abi.encodeWithSignature(
                    "remove(bytes32,uint128,(bytes32,uint256,uint256,int24,int24,uint256,uint256,uint256,uint256),address)",
                    id,
                    SEED,
                    bounds,
                    MANAGER
                )
            );
        require(!ok);
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(MANAGER);
        vault.withdrawIdle();
        assertLivePosition(-120, 120, 1, SEED);
    }

    /// @notice Test both cooldowns and inclusive window endpoints against actual block timestamps.
    function testFirstAndLaterCooldownAndInclusiveExecutionWindow() public {
        activateFixture();
        bytes32 id = vault.positionId();
        vm.warp(10_029);
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.expectRevert(AgreementVault.AdjustmentCooldown.selector);
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        vm.warp(10_030);
        expectWindowRejection(id, 10_031, 10_040);
        expectWindowRejection(id, 10_020, 10_029);
        expectWindowRejection(id, 10_031, 10_029);
        expectWindowRejection(id, 10_029, 10_060);
        bounds.validFrom = 10_000;
        bounds.deadline = 10_030;
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        require(vault.lastAdjustment() == 10_030);
        vm.warp(10_059);
        bounds.validFrom = 10_059;
        bounds.deadline = 10_089;
        vm.expectRevert(AgreementVault.AdjustmentCooldown.selector);
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        vm.warp(10_060);
        bounds.validFrom = 10_060;
        bounds.deadline = 10_090;
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        assertLivePosition(-120, 120, 1, SEED - 2);
    }

    /// @notice Check rejection of an execution interval inconsistent with the C1 window.
    function expectWindowRejection(bytes32 id, uint256 from, uint256 deadline) private {
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        bounds.validFrom = from;
        bounds.deadline = deadline;
        vm.expectRevert(AgreementVault.InvalidWindow.selector);
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
    }

    /// @notice Check the stored tick against the caller's half-open execution envelope.
    function expectPriceRejection(bytes32 id, int24 lower, int24 upper) private {
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        bounds.tickLower = lower;
        bounds.tickUpper = upper;
        vm.expectRevert(AgreementVault.ExecutionTick.selector);
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
    }

    /// @notice Cross a tick boundary and check management against the stored tick and half-open caller interval.
    function testExecutionPriceUsesStoredTickAndHalfOpenSubinterval() public {
        activateAfterCooldown();
        bytes32 id = vault.positionId();
        expectPriceRejection(id, -241, 240);
        expectPriceRejection(id, -240, 241);
        expectPriceRejection(id, 1, 120);
        expectPriceRejection(id, -120, 0);
        expectPriceRejection(id, 0, 0);
        swapToTick(-241);
        expectPriceRejection(id, -240, 240);
        swapToTick(-240);
        (, int24 tick,,) = core.getSlot0(key.toId());
        require(tick == -240);
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        bounds.tickUpper = -239;
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        vm.warp(10_060);
        swapToTick(240);
        expectPriceRejection(id, -240, 240);
        swapToTick(239);
        bounds = adjustmentBounds();
        bounds.tickLower = 239;
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        assertLivePosition(-120, 120, 1, SEED - 2);
    }

    /// @notice Accrue LP fees and verify they cannot satisfy either minimum principal output.
    function testPrincipalOutputMinimumsExcludeFeesOnBothLegs() public {
        activateAfterCooldown();
        swapToTick(-20);
        swapToTick(12);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        (uint256 outA, uint256 outB) = quotePrincipal(-120, 120, SEED / 2, false);
        (uint256 feeA, uint256 feeB) = pendingFees(-120, 120);
        require(feeA > 0 && feeB > 0);
        bounds.minOutput0 = outA + 1;
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.remove(id, SEED / 2, bounds);
        bounds.minOutput0 = outA;
        bounds.minOutput1 = outB + 1;
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.remove(id, SEED / 2, bounds);
        bounds.minOutput1 = outB;
        Balances memory beforeOp = snapshotBalances();
        vm.prank(MANAGER);
        vault.remove(id, SEED / 2, bounds);
        assertSettlement(beforeOp, int256(outA + feeA), int256(outB + feeB));
        assertLivePosition(-120, 120, 1, SEED / 2);
    }

    /// @dev Least L whose rounded-up input equals target. All chosen prices move by <1 base unit per L.
    function liquidityForInput(int24 lower, int24 upper, bool tokenA, uint256 target) private view returns (uint128) {
        uint128 low;
        uint128 high = 2 * SEED;
        while (low < high) {
            uint128 mid = low + (high - low) / 2;
            (uint256 costA, uint256 costB) = quotePrincipal(lower, upper, mid, true);
            if ((tokenA ? costA : costB) < target) low = mid + 1;
            else high = mid;
        }
        (uint256 aCost, uint256 bCost) = quotePrincipal(lower, upper, low, true);
        require((tokenA ? aCost : bCost) == target, "unattainable test input");
        return low;
    }

    /// @notice Offset net A input with fees and challenge the mandate and caller gross limits independently.
    function testGrossCapAndCallerInputLimitWithFeeOffsetA() public {
        checkGrossCap(true);
    }

    /// @notice Offset net B input with fees and challenge the mandate and caller gross limits independently.
    function testGrossCapAndCallerInputLimitWithFeeOffsetB() public {
        checkGrossCap(false);
    }

    /// @notice Exercise gross input bounds with accrued fees offsetting the net settlement delta.
    function checkGrossCap(bool tokenA) private {
        activateAfterCooldown();
        int24 lower = tokenA ? int24(-120) : int24(-240);
        int24 upper = tokenA ? int24(240) : int24(120);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.rerange(id, lower, upper, SEED / 10, bounds);
        swapToTick(tokenA ? int24(-20) : int24(20));
        giveTokens(tokenA ? a : b, address(vault), PRINCIPAL);
        vm.warp(10_060);
        id = vault.positionId();
        bounds = adjustmentBounds();
        bounds.maxInput0 = type(uint256).max;
        bounds.maxInput1 = type(uint256).max;
        (uint256 feeA, uint256 feeB) = pendingFees(lower, upper);
        require((tokenA ? feeA : feeB) > 1);
        uint128 excessive = liquidityForInput(lower, upper, tokenA, PRINCIPAL + 1);
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.add(id, lower, upper, excessive, bounds);
        uint128 exact = liquidityForInput(lower, upper, tokenA, PRINCIPAL);
        if (tokenA) bounds.maxInput0 = PRINCIPAL - 1;
        else bounds.maxInput1 = PRINCIPAL - 1;
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.add(id, lower, upper, exact, bounds);
        bounds.maxInput0 = PRINCIPAL;
        bounds.maxInput1 = PRINCIPAL;
        (uint256 costA, uint256 costB) = quotePrincipal(lower, upper, exact, true);
        Balances memory beforeOp = snapshotBalances();
        vm.prank(MANAGER);
        vault.add(id, lower, upper, exact, bounds);
        assertSettlement(beforeOp, int256(feeA) - int256(costA), int256(feeB) - int256(costB));
        assertLivePosition(lower, upper, 2, exact + SEED / 10);
    }

    /// @notice Leave the replacement leg one base unit short and verify rollback and a successful bounded retry.
    function testSecondRerangeLegOneUnitShortRestoresEverythingAndRetries() public {
        activateAfterCooldown();
        bytes32 oldId = vault.positionId();
        uint128 l = liquidityForInput(-240, 120, false, PRINCIPAL);
        require(hook.lastCheckpoint() == 10_000 && hook.qualifyingSeconds() == 0 && hook.projectedSeconds() == 30);
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        Balances memory beforeOp = snapshotBalances();
        (uint256 outA, uint256 outB) = quotePrincipal(-120, 120, SEED, false);
        (uint256 costA, uint256 costB) = quotePrincipal(-240, 120, l, true);
        require(costB == PRINCIPAL && beforeOp.vaultB + outB == costB - 1 && costA <= beforeOp.vaultA + outA);
        bounds.minOutput0 = outA;
        bounds.minOutput1 = outB;
        vm.expectRevert(
            abi.encodeWithSelector(
                AgreementVault.InsufficientCustody.selector, address(vault), address(b), costB - 1, costB
            )
        );
        vm.prank(MANAGER);
        vault.rerange(oldId, -240, 120, l, bounds);
        assertSettlement(beforeOp, 0, 0);
        require(hook.lastCheckpoint() == 10_000 && hook.qualifyingSeconds() == 0 && hook.projectedSeconds() == 30);
        require(hook.positionId() == oldId && hook.storedQualified() && hook.observedLiquidity() == SEED);
        assertLivePosition(-120, 120, 1, SEED);
        require(
            vault.lastAdjustment() == 0 && core.getLiquidity(key.toId()) == SEED
                && corePositionLiquidity(-240, 120, 2) == 0
        );
        vm.expectRevert(AgreementVault.InvalidOperation.selector);
        vm.prank(address(core));
        vault.unlockCallback(
            abi.encode(
                Operation.Rerange,
                IPoolManager.ModifyLiquidityParams(-240, 120, int256(uint256(l)), bytes32(uint256(2))),
                PRINCIPAL,
                PRINCIPAL
            )
        );
        giveTokens(b, address(vault), 1);
        beforeOp = snapshotBalances();
        b.setProbe(this); // An otherwise authorized treasury attempts nested writes during both legs.
        vm.prank(MANAGER);
        vault.rerange(oldId, -240, 120, l, bounds);
        require(hook.qualifyingSeconds() == 30 && hook.positionId() == vault.positionId());
        require(blockedCalls == 4 && vault.lastAdjustment() == 10_030);
        assertSettlement(beforeOp, int256(outA) - int256(costA), int256(outB) - int256(costB));
        assertLivePosition(-240, 120, 2, l);
        require(corePositionLiquidity(-120, 120, 1) == 0);
    }

    /// @notice Fail each bound of an atomic replacement and retry at the same timestamp.
    function testBothRerangeLegLimitsAreBindingAndSameTimeRetrySucceeds() public {
        activateAfterCooldown();
        swapToTick(-20);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        (uint256 outA, uint256 outB) = quotePrincipal(-120, 120, SEED, false);
        (uint256 inA, uint256 inB) = quotePrincipal(-240, 180, SEED, true);
        (uint256 feeA, uint256 feeB) = pendingFees(-120, 120);
        require(feeA > 0);
        bounds.minOutput0 = outA + 1;
        bounds.minOutput1 = outB;
        bounds.maxInput0 = inA;
        bounds.maxInput1 = inB;
        Balances memory beforeOp = snapshotBalances();
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.rerange(id, -240, 180, SEED, bounds);
        bounds.minOutput0 = outA;
        bounds.maxInput1 = inB - 1;
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.rerange(id, -240, 180, SEED, bounds);
        assertLivePosition(-120, 120, 1, SEED);
        assertSettlement(beforeOp, 0, 0);
        require(vault.lastAdjustment() == 0);
        bounds.maxInput1 = inB;
        vm.prank(MANAGER);
        vault.rerange(id, -240, 180, SEED, bounds);
        assertSettlement(beforeOp, int256(outA + feeA) - int256(inA), int256(outB + feeB) - int256(inB));
        assertLivePosition(-240, 180, 2, SEED);
    }

    /// @notice Attempt each manager operation after stop and require the lifecycle rejection.
    function assertManagerRevoked(bytes32 id) private {
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        int24 lower = vault.positionLower();
        int24 upper = vault.positionUpper();
        int24 nextLower = lower == -120 ? int24(-240) : int24(-120);
        vm.expectRevert(AgreementVault.InvalidPeriod.selector);
        vm.prank(MANAGER);
        vault.add(id, lower, upper, 1, bounds);
        vm.expectRevert(AgreementVault.InvalidPeriod.selector);
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        vm.expectRevert(AgreementVault.InvalidPeriod.selector);
        vm.prank(MANAGER);
        vault.rerange(id, nextLower, 120, SEED, bounds);
    }

    /// @notice Terminate immediately after adjustment and recover principal outside the manager's price envelope.
    function testSameTimestampTerminationAfterAdjustmentAndIndependentExitOutsideEnvelope() public {
        activateAfterCooldown();
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.rerange(id, -240, 240, SEED, bounds);
        swapToTick(300);
        id = vault.positionId();
        vault.terminate();
        assertManagerRevoked(id);
        require(vault.effectiveStop() == vault.lastAdjustment());
        faults.mockCallRevert(address(adapter), "", hex"bad0");
        faults.mockCallRevert(address(escrow), "", hex"bad1");
        (uint256 outA, uint256 outB) = quotePrincipal(-240, 240, SEED, false);
        (uint256 feeA, uint256 feeB) = pendingFees(-240, 240);
        require(outA == 0 && outB > 0 && feeB > 0);
        Balances memory beforeExit = snapshotBalances();
        vault.exitLiquidity();
        require(corePositionLiquidity(-240, 240, 2) == 0 && vault.positionId() == 0);
        vault.withdrawIdle();
        assertCustodyBalances(beforeExit.vaultA + outA + feeA, beforeExit.vaultB + outB + feeB, 0, 0, BUDGET);
        require(
            beforeExit.coreA - a.balanceOf(address(core)) == outA + feeA
                && beforeExit.coreB - b.balanceOf(address(core)) == outB + feeB
        );
        faults.clearMockedCalls();
        require(escrow.refund() == 90_000_000 && escrow.reserved() == 10_000_000);
    }

    /// @notice Order termination before a valid operation and verify all management authority is revoked.
    function testTerminationOrderedFirstRejectsOtherwiseExecutableOperations() public {
        activateAfterCooldown();
        bytes32 id = vault.positionId();
        vault.terminate();
        assertManagerRevoked(id);
        require(vault.lastAdjustment() == 0);
        assertLivePosition(-120, 120, 1, SEED);
    }

    /// @notice Adjust in the last eligible second and require revocation at the scheduled end before finalization.
    function testExactExpiryBeforeFinalizationAfterLastSecondAdjustment() public {
        activateFixture();
        vm.warp(10_299);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = adjustmentBounds();
        vm.prank(MANAGER);
        vault.rerange(id, -240, 240, SEED, bounds);
        vm.warp(10_300);
        id = vault.positionId();
        assertManagerRevoked(id);
        require(vault.recordedStop() == 0 && vault.effectiveStop() == 10_300);
        vault.exitLiquidity();
        vault.withdrawIdle();
        require(corePositionLiquidity(-240, 240, 2) == 0 && vault.lastAdjustment() == 10_299);
        vm.expectRevert(AgreementVault.AlreadyActivated.selector);
        vault.cancel();
        require(escrow.refund() == 0 && escrow.reserved() == BUDGET);
    }
}
