// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {ServiceHook} from "../../src/ServiceHook.sol";
import {IOpeningReferenceAdapter} from "../../src/IOpeningReferenceAdapter.sol";
import {CustodyFixture} from "./CustodyFixture.sol";
import {MockOpeningReferenceAdapter} from "./MockOpeningReferenceAdapter.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {CoreSeedHarness} from "./CoreSeedHarness.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

interface VmLifecycle {
    /// @notice Make the selected read revert with the supplied error bytes.
    function mockCallRevert(address target, bytes calldata data, bytes calldata reason) external;
    /// @notice Restore actual contract calls after an injected read failure.
    function clearMockedCalls() external;
    /// @notice Require the next operation to revert under the selected Foundry expectation.
    function expectRevert() external;
}

abstract contract ActiveFixture is CustodyFixture {
    using StateLibrary for IPoolManager;
    uint128 internal constant SEED = 100_000_000_000;
    uint256 internal constant COST = 598_173_777;
    VmLifecycle internal constant faults = VmLifecycle(address(uint160(uint256(keccak256("hevm cheat code")))));
    IPoolManager internal core;
    ServiceHook internal hook;
    PoolKey internal key;
    MockOpeningReferenceAdapter internal adapter;
    bytes32 internal h;

    /// @notice Bind the test's pool or opening reference before inspecting the current proposal.
    function configureFixture(address boundVault) internal {
        vm.warp(10_000);
        core = new PoolManager(address(this));
        Currency c0 = Currency.wrap(address(a));
        Currency c1 = Currency.wrap(address(b));
        bytes32 initHash =
            keccak256(abi.encodePacked(type(ServiceHook).creationCode, abi.encode(boundVault, core, c0, c1)));
        bytes32 salt;
        address predicted;
        for (uint256 i; i < 1_000_000; ++i) {
            salt = bytes32(i);
            predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initHash)))));
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK == Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG) {
                break;
            }
        }
        hook = new ServiceHook{salt: salt}(boundVault, core, c0, c1);
        require(
            address(hook) == predicted && address(hook).codehash == keccak256(type(ServiceHook).runtimeCode),
            "CREATE2 product"
        );
        key = PoolKey(c0, c1, 3000, 60, IHooks(predicted));
        require(
            PoolId.unwrap(hook.poolId()) == PoolId.unwrap(key.toId()) && hook.poolManager() == core
                && hook.vault() == boundVault
        );
        adapter = new MockOpeningReferenceAdapter();
        AgreementVault.Bindings memory bnd = vault.currentTerms().bindings;
        bnd.poolManager = address(core);
        bnd.hook = predicted;
        bnd.referenceAdapter = address(adapter);
        bnd.referenceSource = address(adapter);
        vault.revise(bnd);
        h = vault.termsHash();
        adapter.publish(
            IOpeningReferenceAdapter.Observation(
                address(adapter), address(a), address(b), 6, 6, 8, 100_000_000, block.timestamp, true
            )
        );
        core.initialize(key, 1 << 96);
    }

    /// @notice Configure the opening pool and prepare the funded vault for a preflight or activation.
    function prepareFundedFixture() internal {
        configureFixture(address(vault));
        fundFixture();
    }

    /// @notice Prepare funded custody and activate the seed against the fixture core.
    function activateFixture() internal {
        prepareFundedFixture();
        vault.activate(h);
    }

    /// @notice Build the execution envelope from the current terms hash and this block's time.
    function adjustmentBounds() internal view returns (AgreementVault.Bounds memory) {
        return AgreementVault.Bounds(h, block.timestamp, block.timestamp, -240, 240, PRINCIPAL, PRINCIPAL, 0, 0);
    }

    /// @notice Move the stored pool price toward a target tick using a separately funded trader.
    function swapToTick(int24 target) internal {
        (uint160 price,,,) = core.getSlot0(key.toId());
        uint160 limit = TickMath.getSqrtPriceAtTick(target);
        if (price == limit) return;
        vm.prank(DONOR);
        CoreSeedHarness trader = new CoreSeedHarness(core, key);
        if (limit < price) {
            a.mint(address(trader), 10 * PRINCIPAL);
            vm.prank(DONOR);
            trader.swapDownTo(limit);
        } else {
            b.mint(address(trader), 10 * PRINCIPAL);
            vm.prank(DONOR);
            trader.swapUpTo(limit);
        }
    }

    /// @notice Read actual core liquidity under the supplied owner and salt at the seed ticks.
    function seedRangeLiquidity(address owner, bytes32 salt) internal view returns (uint128 l) {
        (l,,) = core.getPositionInfo(key.toId(), owner, -120, 120, salt);
    }
}
