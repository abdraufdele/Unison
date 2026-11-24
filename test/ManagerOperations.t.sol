// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../src/AgreementVault.sol";
import {IOpeningReferenceAdapter} from "../src/IOpeningReferenceAdapter.sol";
import {CustodyLock} from "../src/ExactToken.sol";
import {Operation, ServiceHook} from "../src/ServiceHook.sol";
import {CompensationEscrow} from "../src/CompensationEscrow.sol";
import {ActiveFixture} from "./fixtures/ActiveFixture.sol";
import {CoreSeedHarness} from "./fixtures/CoreSeedHarness.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

contract ManagerOperationsTest is ActiveFixture {
    using StateLibrary for IPoolManager;

    struct Balances {
        uint256 vaultA;
        uint256 vaultB;
        uint256 coreA;
        uint256 coreB;
    }

    bool private probeAdd;

    function onTransfer() public override {
        if (!probeAdd) {
            super.onTransfer();
            return;
        }
        require(msg.sender == address(b));
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
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

    function testConsumedGrantsAndManagerLockDuringSettlement() public {
        _start();
        probeAdd = true;
        b.setProbe(this);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        vm.prank(MANAGER);
        vault.add(id, -120, 120, 1, bounds);
        require(blockedCalls == 1 && vault.lastAdjustment() == 10_030);
        _assertLive(-120, 120, 1, SEED + 1);
    }

    function _start() private {
        _active();
        vm.warp(10_030);
    }

    function _bounds() private view returns (AgreementVault.Bounds memory) {
        return AgreementVault.Bounds(h, block.timestamp, block.timestamp, -240, 240, PRINCIPAL, PRINCIPAL, 0, 0);
    }

    function _position(int24 lower, int24 upper, uint256 salt) private view returns (uint128 l) {
        (l,,) = core.getPositionInfo(key.toId(), address(vault), lower, upper, bytes32(salt));
    }

    function _assertLive(int24 lower, int24 upper, uint256 salt, uint128 l) private view {
        require(
            vault.positionLower() == lower && vault.positionUpper() == upper && vault.positionSalt() == bytes32(salt)
        );
        bytes32 id =
            l == 0 ? bytes32(0) : keccak256(abi.encode(key.toId(), address(vault), lower, upper, bytes32(salt)));
        require(vault.positionId() == id && vault.positionLiquidity() == l && _position(lower, upper, salt) == l);
        require(hook.pendingAdd() == 0);
    }

    function _readBalances() private view returns (Balances memory) {
        return Balances(
            a.balanceOf(address(vault)),
            b.balanceOf(address(vault)),
            a.balanceOf(address(core)),
            b.balanceOf(address(core))
        );
    }

    function _settled(Balances memory beforeOp, int256 deltaA, int256 deltaB) private view {
        Balances memory afterOp = _readBalances();
        require(int256(afterOp.vaultA) - int256(beforeOp.vaultA) == deltaA);
        require(int256(afterOp.vaultB) - int256(beforeOp.vaultB) == deltaB);
        require(int256(beforeOp.coreA) - int256(afterOp.coreA) == deltaA);
        require(int256(beforeOp.coreB) - int256(afterOp.coreB) == deltaB);
        require(b.balanceOf(address(escrow)) == BUDGET && escrow.fundedBudget() == BUDGET && escrow.refunded() == 0);
        require(a.balanceOf(MANAGER) == 0 && b.balanceOf(MANAGER) == 0);
    }

    function _principal(int24 lower, int24 upper, uint128 l, bool roundUp) private view returns (uint256, uint256) {
        (uint160 sqrt,,,) = core.getSlot0(key.toId());
        uint160 lo = TickMath.getSqrtPriceAtTick(lower);
        uint160 hi = TickMath.getSqrtPriceAtTick(upper);
        uint160 clipped = sqrt < lo ? lo : (sqrt > hi ? hi : sqrt);
        return (
            SqrtPriceMath.getAmount0Delta(clipped, hi, l, roundUp),
            SqrtPriceMath.getAmount1Delta(lo, clipped, l, roundUp)
        );
    }

    function _fees(int24 lower, int24 upper) private view returns (uint256, uint256) {
        (uint128 l, uint256 lastA, uint256 lastB) =
            core.getPositionInfo(key.toId(), address(vault), lower, upper, vault.positionSalt());
        (uint256 growthA, uint256 growthB) = core.getFeeGrowthInside(key.toId(), lower, upper);
        return (FullMath.mulDiv(growthA - lastA, l, 1 << 128), FullMath.mulDiv(growthB - lastB, l, 1 << 128));
    }

    function _swap(int24 target) private {
        CoreSeedHarness trader = new CoreSeedHarness(core, key);
        (, int24 tick,,) = core.getSlot0(key.toId());
        if (target < tick) {
            a.mint(address(trader), 10 * PRINCIPAL);
            trader.swapDownTo(TickMath.getSqrtPriceAtTick(target));
        } else {
            b.mint(address(trader), 10 * PRINCIPAL);
            trader.swapUpTo(TickMath.getSqrtPriceAtTick(target));
        }
    }

    function testAddPartialFullRemoveAndReopenSameTicks() public {
        _start();
        AgreementVault.Bounds memory bounds = _bounds();
        bytes32 seedId = vault.positionId();
        bounds.maxInput0 = COST;
        bounds.maxInput1 = COST;
        Balances memory beforeOp = _readBalances();
        vm.prank(MANAGER);
        vault.add(seedId, -120, 120, SEED, bounds);
        _settled(beforeOp, -int256(COST), -int256(COST));
        _assertLive(-120, 120, 1, 2 * SEED);

        vm.warp(10_060);
        bounds = _bounds();
        (uint256 outA, uint256 outB) = _principal(-120, 120, 2 * SEED - 1, false);
        beforeOp = _readBalances();
        vm.prank(MANAGER);
        vault.remove(seedId, 2 * SEED - 1, bounds);
        _settled(beforeOp, int256(outA), int256(outB));
        _assertLive(-120, 120, 1, 1); // Below the agreed minimum, still live and removable.

        vm.warp(10_090);
        bounds = _bounds();
        beforeOp = _readBalances();
        vm.prank(MANAGER);
        vault.remove(seedId, 1, bounds);
        _settled(beforeOp, 0, 0);
        _assertLive(-120, 120, 1, 0);

        vm.warp(10_120);
        bounds = _bounds();
        vm.expectRevert(AgreementVault.PositionMismatch.selector);
        vm.prank(MANAGER);
        vault.add(seedId, -120, 120, SEED, bounds);
        vm.prank(MANAGER);
        vault.add(0, -120, 120, SEED, bounds);
        _assertLive(-120, 120, 2, SEED);
        require(_position(-120, 120, 1) == 0 && vault.lastAdjustment() == 10_120);
        vm.warp(10_150);
        bounds = _bounds();
        vm.expectRevert(AgreementVault.PositionMismatch.selector);
        vm.prank(MANAGER);
        vault.remove(seedId, SEED, bounds);
    }

    function testRangeLiquidityAndIdentityRejections() public {
        _start();
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        vm.expectRevert(AgreementVault.PositionMismatch.selector);
        vm.prank(MANAGER);
        vault.add(id, -180, 120, 1, bounds);
        _badRange(id, -120, 120, bounds); // Same range is not a rerange.
        _badRange(id, -60, 120, bounds);
        _badRange(id, -120, 60, bounds);
        _badRange(id, -121, 120, bounds);
        _badRange(id, -120, 121, bounds);
        _badRange(id, -300, 120, bounds);
        _badRange(id, -120, 300, bounds);
        _badRange(id, -300, 240, bounds);
        _badRange(id, 120, -120, bounds);
        _badRange(id, -887280, 120, bounds);
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
        _assertLive(-120, 120, 1, SEED);
        require(vault.lastAdjustment() == 0);
        vm.prank(MANAGER);
        vault.rerange(id, -240, 240, SEED, bounds);
        _assertLive(-240, 240, 2, SEED);
        require(_position(-120, 120, 1) == 0 && vault.bandLower() == -120 && vault.bandUpper() == 120);
    }

    function testWidthCapAlsoAppliesWhenBothEdgesAreWithinExtension() public {
        _ready();
        adapter.publish(
            IOpeningReferenceAdapter.Observation(
                address(adapter), address(a), address(b), 6, 6, 8, 101010101, block.timestamp, true
            )
        );
        vault.activate(h);
        require(vault.bandLower() == -60 && vault.bandUpper() == 240);
        vm.warp(10_030);
        AgreementVault.Bounds memory bounds = _bounds();
        bounds.tickLower = -180;
        bounds.tickUpper = 360;
        bytes32 id = vault.positionId();
        _badRange(id, -180, 360, bounds);
        vm.prank(MANAGER);
        vault.rerange(id, -180, 300, SEED, bounds);
        _assertLive(-180, 300, 2, SEED);
    }

    function _badRange(bytes32 id, int24 lower, int24 upper, AgreementVault.Bounds memory bounds) private {
        vm.expectRevert(AgreementVault.InvalidRange.selector);
        vm.prank(MANAGER);
        vault.rerange(id, lower, upper, 1, bounds);
    }

    function testManagerTermsAndRecipientSurface() public {
        _start();
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
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
        _assertLive(-120, 120, 1, SEED);
    }

    function testFirstAndLaterCooldownAndInclusiveExecutionWindow() public {
        _active();
        bytes32 id = vault.positionId();
        vm.warp(10_029);
        AgreementVault.Bounds memory bounds = _bounds();
        vm.expectRevert(AgreementVault.AdjustmentCooldown.selector);
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        vm.warp(10_030);
        _badWindow(id, 10_031, 10_040);
        _badWindow(id, 10_020, 10_029);
        _badWindow(id, 10_031, 10_029);
        _badWindow(id, 10_029, 10_060);
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
        _assertLive(-120, 120, 1, SEED - 2);
    }

    function _badWindow(bytes32 id, uint256 from, uint256 deadline) private {
        AgreementVault.Bounds memory bounds = _bounds();
        bounds.validFrom = from;
        bounds.deadline = deadline;
        vm.expectRevert(AgreementVault.InvalidWindow.selector);
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
    }

    function _badPrice(bytes32 id, int24 lower, int24 upper) private {
        AgreementVault.Bounds memory bounds = _bounds();
        bounds.tickLower = lower;
        bounds.tickUpper = upper;
        vm.expectRevert(AgreementVault.ExecutionTick.selector);
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
    }

    function testExecutionPriceUsesStoredTickAndHalfOpenSubinterval() public {
        _start();
        bytes32 id = vault.positionId();
        _badPrice(id, -241, 240);
        _badPrice(id, -240, 241);
        _badPrice(id, 1, 120);
        _badPrice(id, -120, 0);
        _badPrice(id, 0, 0);
        _swap(-241);
        _badPrice(id, -240, 240);
        _swap(-240);
        (, int24 tick,,) = core.getSlot0(key.toId());
        require(tick == -240);
        AgreementVault.Bounds memory bounds = _bounds();
        bounds.tickUpper = -239;
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        vm.warp(10_060);
        _swap(240);
        _badPrice(id, -240, 240);
        _swap(239);
        bounds = _bounds();
        bounds.tickLower = 239;
        vm.prank(MANAGER);
        vault.remove(id, 1, bounds);
        _assertLive(-120, 120, 1, SEED - 2);
    }

    function testPrincipalOutputMinimumsExcludeFeesOnBothLegs() public {
        _start();
        _swap(-20);
        _swap(12);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        (uint256 outA, uint256 outB) = _principal(-120, 120, SEED / 2, false);
        (uint256 feeA, uint256 feeB) = _fees(-120, 120);
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
        Balances memory beforeOp = _readBalances();
        vm.prank(MANAGER);
        vault.remove(id, SEED / 2, bounds);
        _settled(beforeOp, int256(outA + feeA), int256(outB + feeB));
        _assertLive(-120, 120, 1, SEED / 2);
    }

    /// @dev Least L whose rounded-up input equals target. All chosen prices move by <1 base unit per L.
    function _liquidityForInput(int24 lower, int24 upper, bool tokenA, uint256 target) private view returns (uint128) {
        uint128 low;
        uint128 high = 2 * SEED;
        while (low < high) {
            uint128 mid = low + (high - low) / 2;
            (uint256 costA, uint256 costB) = _principal(lower, upper, mid, true);
            if ((tokenA ? costA : costB) < target) low = mid + 1;
            else high = mid;
        }
        (uint256 aCost, uint256 bCost) = _principal(lower, upper, low, true);
        require((tokenA ? aCost : bCost) == target, "unattainable test input");
        return low;
    }

    function testGrossCapAndCallerInputLimitWithFeeOffsetA() public {
        _grossCap(true);
    }

    function testGrossCapAndCallerInputLimitWithFeeOffsetB() public {
        _grossCap(false);
    }

    function _grossCap(bool tokenA) private {
        _start();
        int24 lower = tokenA ? int24(-120) : int24(-240);
        int24 upper = tokenA ? int24(240) : int24(120);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        vm.prank(MANAGER);
        vault.rerange(id, lower, upper, SEED / 10, bounds);
        _swap(tokenA ? int24(-20) : int24(20));
        _give(tokenA ? a : b, address(vault), PRINCIPAL);
        vm.warp(10_060);
        id = vault.positionId();
        bounds = _bounds();
        bounds.maxInput0 = type(uint256).max;
        bounds.maxInput1 = type(uint256).max;
        (uint256 feeA, uint256 feeB) = _fees(lower, upper);
        require((tokenA ? feeA : feeB) > 1);
        uint128 excessive = _liquidityForInput(lower, upper, tokenA, PRINCIPAL + 1);
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.add(id, lower, upper, excessive, bounds);
        uint128 exact = _liquidityForInput(lower, upper, tokenA, PRINCIPAL);
        if (tokenA) bounds.maxInput0 = PRINCIPAL - 1;
        else bounds.maxInput1 = PRINCIPAL - 1;
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.add(id, lower, upper, exact, bounds);
        bounds.maxInput0 = PRINCIPAL;
        bounds.maxInput1 = PRINCIPAL;
        (uint256 costA, uint256 costB) = _principal(lower, upper, exact, true);
        Balances memory beforeOp = _readBalances();
        vm.prank(MANAGER);
        vault.add(id, lower, upper, exact, bounds);
        _settled(beforeOp, int256(feeA) - int256(costA), int256(feeB) - int256(costB));
        _assertLive(lower, upper, 2, exact + SEED / 10);
    }

    function testSecondRerangeLegOneUnitShortRestoresEverythingAndRetries() public {
        _start();
        bytes32 oldId = vault.positionId();
        uint128 l = _liquidityForInput(-240, 120, false, PRINCIPAL);
        AgreementVault.Bounds memory bounds = _bounds();
        Balances memory beforeOp = _readBalances();
        (uint256 outA, uint256 outB) = _principal(-120, 120, SEED, false);
        (uint256 costA, uint256 costB) = _principal(-240, 120, l, true);
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
        _settled(beforeOp, 0, 0);
        _assertLive(-120, 120, 1, SEED);
        require(vault.lastAdjustment() == 0 && core.getLiquidity(key.toId()) == SEED && _position(-240, 120, 2) == 0);
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
        _give(b, address(vault), 1);
        beforeOp = _readBalances();
        b.setProbe(this); // An otherwise authorized treasury attempts nested writes during both legs.
        vm.prank(MANAGER);
        vault.rerange(oldId, -240, 120, l, bounds);
        require(blockedCalls == 4 && vault.lastAdjustment() == 10_030);
        _settled(beforeOp, int256(outA) - int256(costA), int256(outB) - int256(costB));
        _assertLive(-240, 120, 2, l);
        require(_position(-120, 120, 1) == 0);
    }

    function testBothRerangeLegLimitsAreBindingAndSameTimeRetrySucceeds() public {
        _start();
        _swap(-20);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        (uint256 outA, uint256 outB) = _principal(-120, 120, SEED, false);
        (uint256 inA, uint256 inB) = _principal(-240, 180, SEED, true);
        (uint256 feeA, uint256 feeB) = _fees(-120, 120);
        require(feeA > 0);
        bounds.minOutput0 = outA + 1;
        bounds.minOutput1 = outB;
        bounds.maxInput0 = inA;
        bounds.maxInput1 = inB;
        Balances memory beforeOp = _readBalances();
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.rerange(id, -240, 180, SEED, bounds);
        bounds.minOutput0 = outA;
        bounds.maxInput1 = inB - 1;
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.rerange(id, -240, 180, SEED, bounds);
        _assertLive(-120, 120, 1, SEED);
        _settled(beforeOp, 0, 0);
        require(vault.lastAdjustment() == 0);
        bounds.maxInput1 = inB;
        vm.prank(MANAGER);
        vault.rerange(id, -240, 180, SEED, bounds);
        _settled(beforeOp, int256(outA + feeA) - int256(inA), int256(outB + feeB) - int256(inB));
        _assertLive(-240, 180, 2, SEED);
    }

    function _revoked(bytes32 id) private {
        AgreementVault.Bounds memory bounds = _bounds();
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

    function testSameTimestampTerminationAfterAdjustmentAndIndependentExitOutsideEnvelope() public {
        _start();
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        vm.prank(MANAGER);
        vault.rerange(id, -240, 240, SEED, bounds);
        _swap(300);
        id = vault.positionId();
        vault.terminate();
        _revoked(id);
        require(vault.effectiveStop() == vault.lastAdjustment());
        faults.mockCallRevert(address(adapter), "", hex"bad0");
        faults.mockCallRevert(address(escrow), "", hex"bad1");
        (uint256 outA, uint256 outB) = _principal(-240, 240, SEED, false);
        (uint256 feeA, uint256 feeB) = _fees(-240, 240);
        require(outA == 0 && outB > 0 && feeB > 0);
        Balances memory beforeExit = _readBalances();
        vault.exitLiquidity();
        require(_position(-240, 240, 2) == 0 && vault.positionId() == 0);
        vault.withdrawIdle();
        _balances(beforeExit.vaultA + outA + feeA, beforeExit.vaultB + outB + feeB, 0, 0, BUDGET);
        require(
            beforeExit.coreA - a.balanceOf(address(core)) == outA + feeA
                && beforeExit.coreB - b.balanceOf(address(core)) == outB + feeB
        );
        faults.clearMockedCalls();
        vm.expectRevert(CompensationEscrow.NotCancelled.selector);
        escrow.refund();
    }

    function testTerminationOrderedFirstRejectsOtherwiseExecutableOperations() public {
        _start();
        bytes32 id = vault.positionId();
        vault.terminate();
        _revoked(id);
        require(vault.lastAdjustment() == 0);
        _assertLive(-120, 120, 1, SEED);
    }

    function testExactExpiryBeforeFinalizationAfterLastSecondAdjustment() public {
        _active();
        vm.warp(10_299);
        bytes32 id = vault.positionId();
        AgreementVault.Bounds memory bounds = _bounds();
        vm.prank(MANAGER);
        vault.rerange(id, -240, 240, SEED, bounds);
        vm.warp(10_300);
        id = vault.positionId();
        _revoked(id);
        require(vault.recordedStop() == 0 && vault.effectiveStop() == 10_300);
        vault.exitLiquidity();
        vault.withdrawIdle();
        require(_position(-240, 240, 2) == 0 && vault.lastAdjustment() == 10_299);
        vm.expectRevert(AgreementVault.AlreadyActivated.selector);
        vault.cancel();
        vm.expectRevert(CompensationEscrow.NotCancelled.selector);
        escrow.refund();
    }
}
