// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {CompensationEscrow} from "../../src/CompensationEscrow.sol";
import {ExactToken} from "../../src/ExactToken.sol";
import {Operation, ServiceHook} from "../../src/ServiceHook.sol";
import {Vm} from "../helpers/Vm.sol";
import {CustodyToken} from "../fixtures/CustodyFixture.sol";
import {CoreSeedHarness} from "../fixtures/CoreSeedHarness.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {ActiveFixture} from "../fixtures/ActiveFixture.sol";

contract AgreementLifecycleTest is ActiveFixture {
    using StateLibrary for IPoolManager;
    event ExitReconciliation(
        uint256 principalA, uint256 principalB, uint256 feeA, uint256 feeB, uint256 treasuryA, uint256 treasuryB
    );

    /// @notice Activate the seed and compare vault owner, salt, core liquidity, opening observation and exact token debits.
    function testActivationOwnsExactSeedAndFixedObservation() public {
        activateFixture();
        require(
            address(vault).code.length <= 24576 && address(hook).code.length <= 24576
                && address(escrow).code.length <= 24576,
            "EIP-170"
        );
        require(
            vault.state() == AgreementVault.State.Active && vault.start() == 10_000 && vault.scheduledEnd() == 10_300
                && vault.effectiveStop() == 0
        );
        require(
            vault.bandLower() == -120 && vault.bandUpper() == 120
                && PoolId.unwrap(vault.positionPoolId()) == PoolId.unwrap(key.toId())
        );
        require(vault.positionSalt() == bytes32(uint256(1)) && vault.positionLiquidity() == SEED);
        require(
            seedRangeLiquidity(address(vault), vault.positionSalt()) == SEED
                && seedRangeLiquidity(address(vault), 0) == 0
                && seedRangeLiquidity(address(hook), vault.positionSalt()) == 0
        );
        (address source,,,,, uint8 decimals, int256 answer, uint256 timestamp, bool complete) =
            vault.openingObservation();
        require(source == address(adapter) && decimals == 8 && answer == 100_000_000 && timestamp == 10_000 && complete);
        require(a.balanceOf(address(core)) == COST && b.balanceOf(address(core)) == COST && hook.pendingAdd() == 0);
        assertCustodyBalances(0, 0, PRINCIPAL - COST, PRINCIPAL - COST, BUDGET);
        vm.expectRevert(AgreementVault.NotFunded.selector);
        vault.activate(h);
        vm.expectRevert(AgreementVault.AlreadyActivated.selector);
        vault.cancel();
        vm.expectRevert(CompensationEscrow.NotTerminal.selector);
        escrow.refund();
        vm.expectRevert(AgreementVault.NotCancelled.selector);
        vault.exitLiquidity();
    }

    /// @notice Vary caller, hash, lifecycle and deadline and require activation to enforce each prerequisite.
    function testActivationCallerHashStateAndCutoff() public {
        configureFixture(address(vault));
        vm.expectRevert(AgreementVault.NotFunded.selector);
        vault.activate(h);
        acceptTerms();
        vm.expectRevert(AgreementVault.NotFunded.selector);
        vault.activate(h);
        vault.fund(h);
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(MANAGER);
        vault.activate(h);
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, bytes32(0), h));
        vault.activate(0);
        vm.warp(vault.activationCutoff());
        vm.expectRevert(AgreementVault.CutoffReached.selector);
        vault.activate(h);
        vault.cancel();
        vm.expectRevert(AgreementVault.NotFunded.selector);
        vault.activate(h);
        require(escrow.refund() == BUDGET);
    }

    /// @notice Expire a previously valid quote and verify activation leaves the agreement unopened.
    function testPreviewExpiresBeforeActivation() public {
        prepareFundedFixture();
        vault.preflightActivation(h);
        vm.warp(block.timestamp + 61);
        vm.expectRevert(AgreementVault.InvalidObservation.selector);
        vault.activate(h);
        assertUnopened();
    }

    /// @notice Bind genuine hook code to another vault and require activation to reject that instance.
    function testActivationRejectsGenuineHookForDifferentVault() public {
        configureFixture(DONOR);
        fundFixture();
        vault.preflightActivation(h);
        vm.expectRevert(AgreementVault.InvalidServiceHook.selector);
        vault.activate(h);
        assertUnopened();
    }

    /// @notice Check that the failed seed left no activated clock, position or opening state.
    function assertUnopened() private view {
        require(vault.state() == AgreementVault.State.Funded && vault.start() == 0 && vault.scheduledEnd() == 0);
        require(
            vault.positionSalt() == 0 && vault.positionLiquidity() == 0 && vault.bandLower() == 0
                && vault.bandUpper() == 0 && PoolId.unwrap(vault.positionPoolId()) == 0
        );
        require(hook.start() == 0 && hook.projectedSeconds() == 0);
        (address source,,,,,,,,) = vault.openingObservation();
        require(
            source == address(0) && hook.pendingAdd() == 0
                && seedRangeLiquidity(address(vault), bytes32(uint256(1))) == 0
        );
        require(
            core.getLiquidity(key.toId()) == 0 && a.balanceOf(address(core)) == 0 && b.balanceOf(address(core)) == 0
        );
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
    }

    /// @notice Break the second seed debit and retry after restoration, checking the initial identity is still fresh.
    function testSecondSeedDebitFailureRollsBackThenRetriesWithSameFreshSalt() public {
        prepareFundedFixture();
        b.setFault(address(vault), address(core), CustodyToken.Fault.FalseReturn);
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        vault.activate(h);
        assertUnopened();
        vm.expectRevert(AgreementVault.InvalidOperation.selector);
        vm.prank(address(core));
        vault.unlockCallback("");
        b.setFault(address(vault), address(core), CustodyToken.Fault.None);
        vault.activate(h);
        require(vault.positionSalt() == bytes32(uint256(1)) && vault.positionLiquidity() == SEED);
    }

    /// @notice Probe both liquidity directions from token callbacks and verify authenticated context and custody guards.
    function testGuardsOnSeedAndRemovalTokenCallbacks() public {
        prepareFundedFixture();
        b.setProbe(this); // Treasury fixture attempts nested fund and cancel during seed payment.
        vault.activate(h);
        require(blockedCalls == 2 && hook.pendingAdd() == 0);
        vault.terminate();
        probe = Probe.Withdrawal;
        vault.exitLiquidity();
        require(blockedCalls == 3 && vault.positionLiquidity() == 0);
    }

    /// @notice Try an unrelated LP addition and an external trader swap against the same product pool.
    function testCoreRejectsIndependentLPAndPermitsTraderSwap() public {
        activateFixture();
        vm.prank(DONOR);
        CoreSeedHarness router = new CoreSeedHarness(core, key);
        a.mint(address(router), PRINCIPAL);
        b.mint(address(router), PRINCIPAL);
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.beforeAddLiquidity.selector,
                abi.encodeWithSelector(ServiceHook.NotVault.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        vm.prank(DONOR);
        router.add(-120, 120, SEED);
        require(seedRangeLiquidity(address(router), 0) == 0);
        vm.prank(DONOR);
        router.swapDownTo(TickMath.getSqrtPriceAtTick(-20));
        (, int24 tick,,) = core.getSlot0(key.toId());
        require(tick == -20);
    }

    /// @notice Challenge callback origin, key, owner and consumed context and require independent rejection.
    function testCallbackCallerPoolOwnerAndReplayChecks() public {
        prepareFundedFixture();
        IPoolManager.ModifyLiquidityParams memory params =
            IPoolManager.ModifyLiquidityParams(-120, 120, int256(uint256(SEED)), bytes32(uint256(1)));
        vm.expectRevert(ServiceHook.NotVault.selector);
        hook.armAdd(Operation.Seed, params);
        vm.expectRevert(ServiceHook.WrongCoreOrPool.selector);
        hook.beforeAddLiquidity(address(vault), key, params, abi.encode(Operation.Seed));
        vm.expectRevert(AgreementVault.InvalidOperation.selector);
        vault.unlockCallback(abi.encode(params));
        vm.expectRevert(AgreementVault.InvalidOperation.selector);
        vm.prank(address(core));
        vault.unlockCallback(abi.encode(params));
        // Isolated caller impersonation exercises the real hook predicates with a pending seed.
        vm.prank(address(vault));
        hook.armAdd(Operation.Seed, params);
        vm.expectRevert(ServiceHook.InvalidAddContext.selector);
        vm.prank(address(vault));
        hook.armAdd(Operation.Seed, params);
        PoolKey memory other = key;
        other.fee = 500;
        vm.expectRevert(ServiceHook.WrongCoreOrPool.selector);
        vm.prank(address(core));
        hook.beforeAddLiquidity(address(vault), other, params, "");
        vm.expectRevert(ServiceHook.NotVault.selector);
        vm.prank(address(core));
        hook.beforeAddLiquidity(MANAGER, key, params, "");
        vm.expectRevert(ServiceHook.InvalidAddContext.selector);
        vm.prank(address(core));
        hook.beforeAddLiquidity(address(vault), key, params, abi.encode(Operation.Rerange));
        params.tickLower = -60;
        expectInvalidAddContext(params);
        params.tickLower = -120;
        params.tickUpper = 180;
        expectInvalidAddContext(params);
        params.tickUpper = 120;
        params.salt = 0;
        expectInvalidAddContext(params);
        params.salt = bytes32(uint256(1));
        params.liquidityDelta--;
        expectInvalidAddContext(params);
        params.liquidityDelta = -int256(uint256(SEED));
        expectInvalidAddContext(params);
        params.liquidityDelta = int256(uint256(SEED));
        vm.prank(address(core));
        require(
            hook.beforeAddLiquidity(address(vault), key, params, abi.encode(Operation.Seed))
                == IHooks.beforeAddLiquidity.selector
        );
        expectInvalidAddContext(params);
        IPoolManager.SwapParams memory swap = IPoolManager.SwapParams(true, -1, 1 << 96);
        vm.expectRevert(ServiceHook.WrongCoreOrPool.selector);
        hook.afterSwap(DONOR, key, swap, BalanceDelta.wrap(0), "");
        vm.expectRevert(ServiceHook.WrongCoreOrPool.selector);
        vm.prank(address(core));
        hook.afterSwap(DONOR, other, swap, BalanceDelta.wrap(0), "");
    }

    /// @notice Call the hook as core without the matching add grant and require InvalidAddContext.
    function expectInvalidAddContext(IPoolManager.ModifyLiquidityParams memory params) private {
        vm.expectRevert(ServiceHook.InvalidAddContext.selector);
        vm.prank(address(core));
        hook.beforeAddLiquidity(address(vault), key, params, abi.encode(Operation.Seed));
    }

    /// @notice Swap before an early stop and reconcile the treasury's two independent principal pulls.
    function testEarlyTerminationIndependentExitAndWithdrawalsAfterSwap() public {
        activateFixture();
        vm.prank(DONOR);
        CoreSeedHarness router = new CoreSeedHarness(core, key);
        a.mint(address(router), PRINCIPAL);
        vm.prank(DONOR);
        router.swapDownTo(TickMath.getSqrtPriceAtTick(-20));
        (uint160 sqrt,,,) = core.getSlot0(key.toId());
        uint256 principalA = SqrtPriceMath.getAmount0Delta(sqrt, TickMath.getSqrtPriceAtTick(120), SEED, false);
        uint256 principalB = SqrtPriceMath.getAmount1Delta(TickMath.getSqrtPriceAtTick(-120), sqrt, SEED, false);
        (uint256 growthA, uint256 growthB) = core.getFeeGrowthInside(key.toId(), -120, 120);
        (, uint256 lastA, uint256 lastB) =
            core.getPositionInfo(key.toId(), address(vault), -120, 120, vault.positionSalt());
        uint256 feeA = FullMath.mulDiv(growthA - lastA, SEED, 1 << 128);
        uint256 feeB = FullMath.mulDiv(growthB - lastB, SEED, 1 << 128);
        require(feeA > 0 && feeB == 0);
        // Isolate the escrow-to-recipient route on principal token B. Also fail ALL adapter/escrow calls.
        b.setFault(address(escrow), address(this), CustodyToken.Fault.Revert);
        faults.mockCallRevert(address(adapter), "", hex"bad0");
        faults.mockCallRevert(address(escrow), "", hex"bad1");
        vm.warp(10_010);
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(MANAGER);
        vault.terminate();
        vault.terminate();
        require(
            vault.state() == AgreementVault.State.Terminated && vault.effectiveStop() == 10_010
                && vault.positionLiquidity() == SEED
        );
        assertCustodyBalances(0, 0, PRINCIPAL - COST, PRINCIPAL - COST, BUDGET);
        vault.withdrawIdle();
        uint256 coreA = a.balanceOf(address(core));
        uint256 coreB = b.balanceOf(address(core));
        vm.recordLogs();
        vault.exitLiquidity();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory receipt = logs[logs.length - 1];
        require(
            receipt.emitter == address(vault)
                && receipt.topics[0]
                    == keccak256("LiquidityExited(bytes32,bytes32,uint128,int128,int128,int128,int128)")
        );
        require(receipt.topics[1] == PoolId.unwrap(key.toId()) && receipt.topics[2] == vault.positionSalt());
        require(
            keccak256(receipt.data) == keccak256(abi.encode(SEED, principalA, principalB, feeA, feeB)),
            "principal and fee receipt"
        );
        require(
            coreA - a.balanceOf(address(core)) == principalA + feeA
                && coreB - b.balanceOf(address(core)) == principalB + feeB
        );
        require(seedRangeLiquidity(address(vault), vault.positionSalt()) == 0);
        assertCustodyBalances(PRINCIPAL - COST, PRINCIPAL - COST, principalA + feeA, principalB + feeB, BUDGET);
        vault.exitLiquidity();
        vault.withdrawIdle();
        vault.withdrawIdle();
        vault.terminate();
        uint256 treasuryA = PRINCIPAL - COST + principalA + feeA;
        uint256 treasuryB = PRINCIPAL - COST + principalB + feeB;
        assertCustodyBalances(treasuryA, treasuryB, 0, 0, BUDGET);
        require(
            hook.stopped() && hook.positionId() == 0 && hook.qualifyingSeconds() == 10 && hook.projectedSeconds() == 10
        );
        require(treasuryA > PRINCIPAL && treasuryB < PRINCIPAL);
        emit ExitReconciliation(principalA, principalB, feeA, feeB, treasuryA, treasuryB);
        faults.clearMockedCalls();
        vm.warp(vault.activationCutoff());
        vm.expectRevert(AgreementVault.AlreadyActivated.selector);
        vm.prank(DONOR);
        vault.cancel();
        require(
            !vault.cancelled() && escrow.refundable() == 96_666_667 && vault.state() == AgreementVault.State.Terminated
        );
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        escrow.refund();
        require(escrow.refunded() == 0 && escrow.reserved() == 3_333_333);
    }

    /// @notice Exit at effective expiry before recording the stop and verify later finalization uses the original end.
    function testExactExpiryExitBeforeDelayedFinalization() public {
        activateFixture();
        uint256 end = vault.scheduledEnd();
        vm.warp(end - 1);
        vm.expectRevert(AgreementVault.InvalidPeriod.selector);
        vault.finalizeExpiry();
        require(vault.state() == AgreementVault.State.Active);
        vm.warp(end);
        require(
            vault.state() == AgreementVault.State.Expired && vault.effectiveStop() == end && vault.recordedStop() == 0
        );
        vm.expectRevert(AgreementVault.AlreadyActivated.selector);
        vault.cancel();
        vm.expectRevert(AgreementVault.NotTreasury.selector);
        vm.prank(MANAGER);
        vault.exitLiquidity();
        vault.exitLiquidity();
        vault.withdrawIdle();
        require(
            vault.recordedStop() == 0 && hook.stopped() && hook.qualifyingSeconds() == 300 && hook.positionId() == 0
        );
        vm.warp(end + 77);
        vm.prank(DONOR);
        vault.finalizeExpiry();
        vault.finalizeExpiry();
        vault.terminate();
        require(
            vault.recordedStop() == end && vault.state() == AgreementVault.State.Expired && escrow.refundable() == 0
        );
        require(escrow.refund() == 0 && escrow.reserved() == BUDGET);
        require(b.balanceOf(address(escrow)) == BUDGET && escrow.refunded() == 0);
    }

    /// @notice Fail removal and withdrawal separately and verify each can be retried with the same asset rights.
    function testRemovalAndWithdrawalFailuresPreserveSeparateRetries() public {
        activateFixture();
        vault.terminate();
        b.setFault(address(core), address(vault), CustodyToken.Fault.ShortReceipt);
        vm.expectRevert(abi.encodeWithSelector(ExactToken.UnexpectedBalance.selector, address(b), address(vault)));
        vault.exitLiquidity();
        require(vault.positionLiquidity() == SEED && seedRangeLiquidity(address(vault), vault.positionSalt()) == SEED);
        assertCustodyBalances(0, 0, PRINCIPAL - COST, PRINCIPAL - COST, BUDGET);
        b.setFault(address(core), address(vault), CustodyToken.Fault.None);
        vault.exitLiquidity();
        uint256 idleA = a.balanceOf(address(vault));
        uint256 idleB = b.balanceOf(address(vault));
        b.setFault(address(vault), address(this), CustodyToken.Fault.FalseReturn);
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        vault.withdrawIdle();
        assertCustodyBalances(0, 0, idleA, idleB, BUDGET);
        b.setFault(address(vault), address(this), CustodyToken.Fault.None);
        vault.withdrawIdle();
        assertCustodyBalances(idleA, idleB, 0, 0, BUDGET);
    }
}
