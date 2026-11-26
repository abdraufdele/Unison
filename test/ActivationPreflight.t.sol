// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {AgreementVault} from "../src/AgreementVault.sol";
import {SeedPool} from "../src/SeedPool.sol";
import {IOpeningReferenceAdapter} from "../src/IOpeningReferenceAdapter.sol";
import {CustodyFixture} from "./fixtures/CustodyFixture.sol";
import {MockOpeningReferenceAdapter} from "./fixtures/MockOpeningReferenceAdapter.sol";
import {TestOnlySeedHook, CoreSeedHarness} from "./fixtures/CoreSeedHarness.sol";

interface PreflightVm {
    /// @notice Install fixture runtime code at the requested test address.
    function etch(address where, bytes calldata code) external;
    /// @notice Return fixture data for the selected contract read.
    function mockCall(address to, bytes calldata data, bytes calldata result) external;
}

contract ActivationPreflightTest is CustodyFixture {
    using StateLibrary for IPoolManager;

    PreflightVm private constant fixtureVm = PreflightVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant HOOK = address(0x10840); // beforeAddLiquidity + afterSwap only
    uint128 private constant SEED = 100_000_000_000;
    uint160 private constant PARITY = 1 << 96;
    IPoolManager private core;
    PoolKey private key;
    MockOpeningReferenceAdapter private adapter;
    CoreSeedHarness private payer;
    bytes32 private hash;
    event CoreSeedCompared(int24 storedTick, uint256 quotedA, uint256 quotedB, int128 principalA, int128 principalB);

    /// @notice Bind the test's pool or opening reference before inspecting the current proposal.
    function configureFixture() private {
        vm.warp(10_000);
        core = new PoolManager(address(this));
        // Forge installs stateless test bytecode at an address with the real core dispatch bits.
        fixtureVm.etch(HOOK, type(TestOnlySeedHook).runtimeCode);
        key = PoolKey(Currency.wrap(address(a)), Currency.wrap(address(b)), 3000, 60, IHooks(HOOK));
        payer = new CoreSeedHarness(core, key);
        adapter = new MockOpeningReferenceAdapter();
        AgreementVault.Bindings memory bindings = vault.currentTerms().bindings;
        bindings.referenceAdapter = address(adapter);
        bindings.referenceSource = address(adapter);
        bindings.poolManager = address(core);
        bindings.hook = HOOK;
        vault.revise(bindings);
        hash = vault.termsHash();
        publishOpening(100_000_000);
    }

    /// @notice Supply a mock observation with the requested answer for this preflight.
    function publishOpening(int256 answer) private {
        adapter.publish(
            IOpeningReferenceAdapter.Observation(
                address(adapter), address(a), address(b), 6, 6, 8, answer, block.timestamp, true
            )
        );
    }

    /// @notice Configure the opening pool and prepare the funded vault for a preflight or activation.
    function prepareFundedFixture(uint160 sqrtPrice) private {
        configureFixture();
        core.initialize(key, sqrtPrice);
        fundFixture();
    }

    /// @notice Inspect a funded parity pool and reconcile identity, two seed legs and separate custody balances.
    function testFundedParityReadsAcceptedIdentityAndActualCustodies() public {
        prepareFundedFixture(PARITY);
        AgreementVault.ActivationPreflight memory q = vault.preflightActivation(hash);
        require(q.observation.answer == 100_000_000 && q.observation.updatedAt == block.timestamp, "fresh reference");
        require(q.lower == -120 && q.upper == 120 && q.seed.liquidity == SEED, "C1 seed");
        require(q.seed.manager == core && PoolId.unwrap(q.seed.id) == keccak256(abi.encode(key)), "manager/id");
        require(keccak256(abi.encode(q.seed.key)) == keccak256(abi.encode(key)), "full key");
        require(q.seed.tick == 0 && q.seed.sqrtPriceX96 == PARITY, "slot0");
        require(q.available0 == PRINCIPAL && q.available1 == PRINCIPAL && q.escrowBalance == BUDGET, "available");
        require(core.getLiquidity(key.toId()) == 0 && vault.state() == AgreementVault.State.Funded, "read only");
        compareSeedSettlement(q);
        assertCustodyBalances(0, 0, PRINCIPAL, PRINCIPAL, BUDGET);
        require(escrow.fundedBudget() == BUDGET && escrow.refunded() == 0, "budget moved");
    }

    /// @notice Place the price between ticks and compare the quote with actual core settlement.
    function testInteriorUsesActualSqrtPriceBetweenTicks() public {
        uint160 sqrt =
            TickMath.getSqrtPriceAtTick(23) + (TickMath.getSqrtPriceAtTick(24) - TickMath.getSqrtPriceAtTick(23)) / 2;
        prepareFundedFixture(sqrt);
        AgreementVault.ActivationPreflight memory q = vault.preflightActivation(hash);
        require(q.seed.tick == 23 && q.seed.sqrtPriceX96 == sqrt, "intra-tick price");
        compareSeedSettlement(q);
    }

    /// @notice Seed at the inclusive lower edge and verify that only currency zero is required.
    function testLowerInclusiveCanRequireOnlyA() public {
        prepareFundedFixture(TickMath.getSqrtPriceAtTick(-120));
        AgreementVault.ActivationPreflight memory q = vault.preflightActivation(hash);
        require(q.seed.tick == q.lower && q.seed.amount1 == 0 && q.seed.amount0 > 0, "lower edge");
        compareSeedSettlement(q);
    }

    /// @notice Place the stored tick at the exclusive upper edge and require preflight rejection.
    function testUpperExclusiveRejectsInitializedUpperTick() public {
        prepareFundedFixture(TickMath.getSqrtPriceAtTick(120));
        expectOutsideBand(120, -120, 120);
    }

    /// @notice Cross downward to parity and require band membership to follow stored tick minus one.
    function testDownwardCrossToPriceOneUsesStoredMinusOne() public {
        prepareFundedFixture(TickMath.getSqrtPriceAtTick(1));
        CoreSeedHarness background = new CoreSeedHarness(core, key);
        a.mint(address(background), PRINCIPAL);
        b.mint(address(background), PRINCIPAL);
        background.add(0, 60, SEED);
        background.swapDownTo(PARITY);
        (uint160 sqrt, int24 tick,,) = core.getSlot0(key.toId());
        require(sqrt == PARITY && tick == -1 && TickMath.getTickAtSqrtPrice(sqrt) == 0, "real downward crossing");
        publishOpening(101_010_102); // [0,240): sqrt is on the lower edge, stored tick is outside.
        expectOutsideBand(-1, 0, 240);
        publishOpening(99_009_900); // [-240,0): same core state, stored tick is inside.
        AgreementVault.ActivationPreflight memory q = vault.preflightActivation(hash);
        require(
            q.seed.tick == -1 && q.seed.sqrtPriceX96 == PARITY && q.seed.amount0 == 0 && q.seed.amount1 > 0,
            "upper ratio"
        );
        compareSeedSettlement(q);
    }

    /// @notice Require the stored core tick to fail the quoted opening band.
    function expectOutsideBand(int24 tick, int24 lower, int24 upper) private {
        vm.expectRevert(abi.encodeWithSelector(SeedPool.TickOutsideBand.selector, tick, lower, upper));
        vault.preflightActivation(hash);
    }

    /// Each short trial starts at the preflight pool state. The real add rolls back during ERC-20 settlement.
    function compareSeedSettlement(AgreementVault.ActivationPreflight memory q) private {
        if (q.seed.amount0 > 0) expectShortSeedRollback(q, true);
        if (q.seed.amount1 > 0) expectShortSeedRollback(q, false);
        a.mint(address(payer), q.seed.amount0);
        b.mint(address(payer), q.seed.amount1);
        uint256 before0 = a.balanceOf(address(core));
        uint256 before1 = b.balanceOf(address(core));
        BalanceDelta principal = payer.add(q.lower, q.upper, SEED);
        require(
            int256(principal.amount0()) == -int256(q.seed.amount0)
                && int256(principal.amount1()) == -int256(q.seed.amount1),
            "principal deltas"
        );
        require(
            a.balanceOf(address(core)) - before0 == q.seed.amount0
                && b.balanceOf(address(core)) - before1 == q.seed.amount1,
            "core receipts"
        );
        require(a.balanceOf(address(payer)) == 0 && b.balanceOf(address(payer)) == 0, "exact inventory");
        (uint128 liquidity,,) = core.getPositionInfo(q.seed.id, address(payer), q.lower, q.upper, bytes32(0));
        require(liquidity == SEED, "actual test payer position");
        emit CoreSeedCompared(q.seed.tick, q.seed.amount0, q.seed.amount1, principal.amount0(), principal.amount1());
    }

    /// @notice Fund one leg a single base unit short and verify that seeding reverts.
    function expectShortSeedRollback(AgreementVault.ActivationPreflight memory q, bool shortA) private {
        uint256 snapshot = vm.snapshotState();
        uint256 balance0 = q.seed.amount0 - (shortA ? 1 : 0);
        uint256 balance1 = q.seed.amount1 - (shortA ? 0 : 1);
        a.mint(address(payer), balance0);
        b.mint(address(payer), balance1);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x11))); // mock ERC-20 debit underflow
        payer.add(q.lower, q.upper, SEED);
        (uint128 liquidity,,) = core.getPositionInfo(q.seed.id, address(payer), q.lower, q.upper, bytes32(0));
        require(
            liquidity == 0 && a.balanceOf(address(payer)) == balance0 && b.balanceOf(address(payer)) == balance1,
            "short add rollback"
        );
        require(vm.revertToStateAndDelete(snapshot));
    }

    /// @notice Initialize alternate keys or cores and verify they cannot provide the accepted pool's slot zero.
    function testOtherInitializedKeysAndManagerCannotSupplySlot0() public {
        configureFixture();
        fundFixture();
        PoolKey memory other = key;
        other.fee = 500;
        core.initialize(other, PARITY);
        other = key;
        other.tickSpacing = 10;
        core.initialize(other, PARITY);
        other = key;
        other.hooks = IHooks(address(0));
        core.initialize(other, PARITY);
        other = key;
        other.currency1 = Currency.wrap(address(type(uint160).max));
        core.initialize(other, PARITY);
        IPoolManager second = new PoolManager(address(this));
        second.initialize(key, PARITY);
        PoolId expected = key.toId();
        vm.expectRevert(abi.encodeWithSelector(SeedPool.UninitializedPool.selector, expected));
        vault.preflightActivation(hash);
        core.initialize(key, PARITY);
        vault.preflightActivation(hash);
    }

    /// @notice Remove code from the configured hook and require the feasibility check to fail.
    function testConfiguredHookMustHaveCode() public {
        prepareFundedFixture(PARITY);
        fixtureVm.etch(HOOK, "");
        vm.expectRevert(SeedPool.InvalidPoolConfiguration.selector);
        vault.preflightActivation(hash);
    }

    /// @notice Initialize another pool with different callback bits and require the hook mask check.
    function testInitializedPoolWithDifferentCallbackFlagsIsRejected() public {
        configureFixture();
        address onlyBeforeAdd = address(0x10800);
        fixtureVm.etch(onlyBeforeAdd, type(TestOnlySeedHook).runtimeCode);
        AgreementVault.Bindings memory bindings = vault.currentTerms().bindings;
        bindings.hook = onlyBeforeAdd;
        vault.revise(bindings);
        hash = vault.termsHash();
        key.hooks = IHooks(onlyBeforeAdd);
        core.initialize(key, PARITY);
        fundFixture();
        vm.expectRevert(SeedPool.InvalidPoolConfiguration.selector);
        vault.preflightActivation(hash);
    }

    /// @notice Try preflight with a stale commitment, wrong lifecycle state and at the exact cutoff.
    function testWrongStateHashAndExactCutoff() public {
        configureFixture();
        vm.expectRevert(AgreementVault.NotFunded.selector);
        vault.preflightActivation(hash);
        acceptTerms();
        giveTokens(a, address(vault), PRINCIPAL);
        giveTokens(b, address(vault), PRINCIPAL);
        giveTokens(b, address(escrow), BUDGET);
        vm.expectRevert(AgreementVault.NotFunded.selector);
        vault.preflightActivation(hash);
        vault.fund(hash);
        bytes32 wrong = bytes32(uint256(123));
        vm.expectRevert(abi.encodeWithSelector(AgreementVault.WrongTermsHash.selector, wrong, hash));
        vault.preflightActivation(wrong);
        vm.warp(vault.activationCutoff());
        vm.expectRevert(AgreementVault.CutoffReached.selector);
        vault.preflightActivation(hash);
        vault.cancel();
        vm.expectRevert(AgreementVault.NotFunded.selector);
        vault.preflightActivation(hash);
    }

    /// @notice Change chain ID after funding and verify that otherwise feasible activation is rejected.
    function testWrongChainRejectsOtherwiseValidPreflight() public {
        prepareFundedFixture(PARITY);
        vm.chainId(vault.creationChainId() + 1);
        vm.expectRevert(AgreementVault.WrongChain.selector);
        vault.preflightActivation(hash);
    }

    /// @notice Let the observation age or reduce custody after a valid quote and require a fresh check to fail.
    function testPreviouslyValidPreviewExpiresAndRechecksFullFunding() public {
        prepareFundedFixture(PARITY);
        giveTokens(a, address(vault), 17);
        giveTokens(b, address(escrow), 11);
        AgreementVault.ActivationPreflight memory q = vault.preflightActivation(hash);
        require(
            q.available0 == PRINCIPAL + 17 && q.escrowBalance == BUDGET + 11 && escrow.fundedBudget() == BUDGET, "gifts"
        );
        vm.warp(block.timestamp + 61);
        vm.expectRevert(AgreementVault.InvalidObservation.selector);
        vault.preflightActivation(hash);
        publishOpening(100_000_000);
        vault.preflightActivation(hash);
        // Negative fixture only: simulate a custody loss neither product contract permits.
        vm.prank(address(vault));
        a.transfer(DONOR, 18);
        expectCustodyShortfall(address(vault), address(a), PRINCIPAL);
        a.mint(address(vault), 1);
        vm.prank(address(vault));
        b.transfer(DONOR, 1);
        expectCustodyShortfall(address(vault), address(b), PRINCIPAL);
        b.mint(address(vault), 1);
        vm.prank(address(escrow));
        b.transfer(DONOR, 12);
        expectCustodyShortfall(address(escrow), address(b), BUDGET);
    }

    /// @notice Check that preflight reports the missing base-unit custody for the correct holder.
    function expectCustodyShortfall(address holder, address token, uint256 required) private {
        vm.expectRevert(
            abi.encodeWithSelector(AgreementVault.InsufficientCustody.selector, holder, token, required - 1, required)
        );
        vault.preflightActivation(hash);
    }

    /// @notice Change escrow credit or refund information and require preflight to revalidate the binding.
    function testPreflightRechecksBoundEscrowCreditAndRefund() public {
        prepareFundedFixture(PARITY);
        fixtureVm.mockCall(address(escrow), abi.encodeCall(escrow.fundedBudget, ()), abi.encode(BUDGET - 1));
        expectInvalidEscrow();
        fixtureVm.mockCall(address(escrow), abi.encodeCall(escrow.fundedBudget, ()), abi.encode(BUDGET));
        fixtureVm.mockCall(address(escrow), abi.encodeCall(escrow.refunded, ()), abi.encode(1));
        expectInvalidEscrow();
        fixtureVm.mockCall(address(escrow), abi.encodeCall(escrow.refunded, ()), abi.encode(0));
        fixtureVm.mockCall(address(escrow), abi.encodeCall(escrow.managerRecipient, ()), abi.encode(DONOR));
        expectInvalidEscrow();
    }

    /// @notice Check that the funded preflight rejects inconsistent escrow identity or credit.
    function expectInvalidEscrow() private {
        vm.expectRevert(AgreementVault.InvalidEscrow.selector);
        vault.preflightActivation(hash);
    }

    /// @notice Gift extra B and check that it cannot raise the agreed gross seed input limit.
    function testGiftsCannotRelaxGrossBSeedCap() public {
        prepareFundedFixture(TickMath.getSqrtPriceAtTick(46054));
        publishOpening(10_000_000_000); // about 100 B per A; the B leg exceeds its cap
        giveTokens(b, address(vault), 100 * PRINCIPAL);
        vm.expectRevert(AgreementVault.SeedInputLimit.selector);
        vault.preflightActivation(hash);
    }

    /// @notice Gift extra A and check that it cannot raise the agreed gross seed input limit.
    function testGiftsCannotRelaxGrossASeedCap() public {
        prepareFundedFixture(TickMath.getSqrtPriceAtTick(-46054));
        publishOpening(1_000_000); // about 0.01 B per A
        giveTokens(a, address(vault), 100 * PRINCIPAL);
        vm.expectRevert(AgreementVault.SeedInputLimit.selector);
        vault.preflightActivation(hash);
    }

    /// @notice Fill capacity at either seed edge and require preflight to reject the additional liquidity.
    function testSeedNeedsHeadroomAtBothCoreTicks() public {
        prepareFundedFixture(PARITY);
        CoreSeedHarness background = new CoreSeedHarness(core, key);
        uint128 limit = Pool.tickSpacingToMaxLiquidityPerTick(60);
        a.mint(address(background), limit);
        b.mint(address(background), limit);
        uint256 snapshot = vm.snapshotState();
        background.add(-180, -120, limit);
        vm.expectRevert(SeedPool.TickCapacityExceeded.selector);
        vault.preflightActivation(hash);
        require(vm.revertToStateAndDelete(snapshot));
        background.add(120, 180, limit);
        vm.expectRevert(SeedPool.TickCapacityExceeded.selector);
        vault.preflightActivation(hash);
    }
}
