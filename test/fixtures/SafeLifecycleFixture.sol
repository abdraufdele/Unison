// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    SafeCreationFixture,
    Vm,
    AgreementVault,
    Enum,
    CustodyToken,
    MockOpeningReferenceAdapter
} from "./SafeCreationFixture.sol";
import {ServicePoolFixture, ServiceHook, PoolKey, IPoolManager, Currency} from "./ServicePoolFixture.sol";
import {CompensationEscrow} from "../../src/CompensationEscrow.sol";
import {IOpeningReferenceAdapter} from "../../src/IOpeningReferenceAdapter.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

abstract contract SafeLifecycleFixture is SafeCreationFixture {
    using StateLibrary for IPoolManager;
    uint256 internal constant PRINCIPAL = 2_000_000_000;
    uint256 internal constant BUDGET = 100_000_000;
    uint128 internal constant SEED = 100_000_000_000;
    uint256 internal constant SEED_COST = 598_173_777;
    AgreementVault internal vault;
    CompensationEscrow internal escrow;
    ServiceHook internal hook;
    PoolKey internal key;
    CustodyToken internal a;
    CustodyToken internal b;
    bytes32 internal terms;

    /// @notice Finish the actual custody bindings and pool initialization before any consent.
    function setUp() public override {
        super.setUp();
        vault = createWithPair(0, 1, Enum.Operation.DelegateCall);
        require(vault.treasury() == address(safe) && vault.manager() == manager);
        a = CustodyToken(draft.token0);
        b = CustodyToken(draft.token1);
        escrow = new CompensationEscrow(address(vault), b, address(safe), manager);
        require(escrow.treasuryRecipient() == address(safe) && escrow.managerRecipient() == manager);
        require(address(escrow.paymentToken()) == address(b) && escrow.vault() == address(vault));
        IPoolManager core = IPoolManager(draft.poolManager);
        (hook, key) =
            ServicePoolFixture.install(address(vault), core, Currency.wrap(address(a)), Currency.wrap(address(b)));
        draft.escrow = address(escrow);
        draft.hook = address(hook);
        safeCall(address(vault), abi.encodeCall(vault.revise, (draft)), 0, 1);
        core.initialize(key, 1 << 96);
        terms = vault.termsHash();
        require(vault.revision() == 2 && vault.state() == AgreementVault.State.Draft);
        require(terms == keccak256(abi.encode(vault.TERMS_SCHEMA(), vault.currentTerms())));
        require(vault.managerAcceptedRevision() == 0 && vault.treasuryAcceptedRevision() == 0);
        a.mint(address(safe), PRINCIPAL);
        b.mint(address(safe), PRINCIPAL + BUDGET);
        refreshReference();
    }

    /// @notice Publish a local parity observation at the current block timestamp.
    function refreshReference() internal {
        MockOpeningReferenceAdapter(draft.referenceAdapter)
            .publish(
                IOpeningReferenceAdapter.Observation(
                    draft.referenceSource, address(a), address(b), 6, 6, 8, 100_000_000, block.timestamp, true
                )
            );
    }

    /// @notice Prepare a treasury CALL against the current Safe nonce.
    function requestCall(address target, bytes memory data) internal view returns (Request memory) {
        return Request(target, data, Enum.Operation.Call, safe.nonce());
    }

    /// @notice Verify the result, emitted hash and consumed nonce for a previously signed request.
    function submitSigned(Request memory r, bytes memory sigs) internal returns (Vm.Log[] memory logs) {
        bytes32 hash = digest(r);
        vm.recordLogs();
        require(execute(r, sigs), "failed Safe action");
        logs = vm.getRecordedLogs();
        assertSuccess(logs, hash);
        require(safe.nonce() == r.nonce + 1);
    }

    /// @notice Sign one operation with only the named pair and submit from the independent executor.
    function safeCall(address target, bytes memory data, uint256 first, uint256 second)
        internal
        returns (Vm.Log[] memory)
    {
        Request memory r = requestCall(target, data);
        return submitSigned(r, signedPair(digest(r), owners[first], owners[second]));
    }

    /// @notice Check an inner failure that reverts the entire default-gas Safe transaction.
    function rejectedVaultCall(bytes memory data) internal {
        Request memory r = requestCall(address(vault), data);
        bytes memory sigs = signedPair(digest(r), owners[0], owners[1]);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GS013"));
        execute(r, sigs);
        require(safe.nonce() == r.nonce);
    }

    /// @notice Record independent consent by the Safe and manager to identical finalized terms.
    function acceptBoth() internal {
        safeCall(address(vault), abi.encodeCall(vault.accept, (terms)), 0, 1);
        vm.prank(manager);
        vault.accept(terms);
        require(
            vault.treasuryAcceptedRevision() == vault.revision() && vault.managerAcceptedRevision() == vault.revision()
        );
    }

    /// @notice Check complete funding against the exact allowances and the three independent custody balances.
    function fundAccepted() internal {
        safeCall(address(a), abi.encodeCall(a.approve, (address(vault), PRINCIPAL)), 0, 1);
        safeCall(address(b), abi.encodeCall(b.approve, (address(vault), PRINCIPAL + BUDGET)), 0, 2);
        require(
            a.allowance(address(safe), address(vault)) == PRINCIPAL
                && b.allowance(address(safe), address(vault)) == PRINCIPAL + BUDGET
        );
        safeCall(address(vault), abi.encodeCall(vault.fund, (terms)), 1, 2);
        require(a.allowance(address(safe), address(vault)) == 0 && b.allowance(address(safe), address(vault)) == 0);
        require(a.balanceOf(address(safe)) == 0 && b.balanceOf(address(safe)) == 0);
        require(a.balanceOf(address(vault)) == PRINCIPAL && b.balanceOf(address(vault)) == PRINCIPAL);
        require(b.balanceOf(address(escrow)) == BUDGET && escrow.fundedBudget() == BUDGET);
    }

    /// @notice Open at parity and verify real core position, vault idle legs and the first service observation.
    function activateFunded() internal {
        Vm.Log[] memory logs = safeCall(address(vault), abi.encodeCall(vault.activate, (terms)), 0, 1);
        Vm.Log memory activated = eventFrom(
            logs,
            address(vault),
            keccak256("Activated(bytes32,bytes32,bytes32,int24,int24,uint128,uint256,uint256,uint256,uint256)")
        );
        require(
            activated.topics.length == 4 && activated.topics[1] == terms
                && activated.topics[2] == PoolId.unwrap(key.toId()) && activated.topics[3] == vault.positionSalt()
        );
        require(
            keccak256(activated.data)
                == keccak256(
                    abi.encode(
                        int24(-120), int24(120), SEED, SEED_COST, SEED_COST, block.timestamp, block.timestamp + 300
                    )
                )
        );
        require(vault.start() == block.timestamp && vault.scheduledEnd() == block.timestamp + 300);
        require(vault.positionId() != 0 && hook.positionId() == vault.positionId() && coreLiquidity() == SEED);
        (bool qualified, uint8 failures) = hook.qualification();
        require(qualified && failures == 0 && hook.projectedSeconds() == 0);
        require(
            a.balanceOf(address(vault)) == PRINCIPAL - SEED_COST && b.balanceOf(address(vault)) == PRINCIPAL - SEED_COST
        );
    }

    /// @notice Start a fresh signed and fully funded period for an isolated closeout scenario.
    function openPeriod() internal {
        acceptBoth();
        fundAccepted();
        activateFunded();
    }

    /// @notice Read liquidity from the core under the vault's pool, owner, actual ticks and salt.
    function coreLiquidity() internal view returns (uint128 l) {
        (l,,) = IPoolManager(draft.poolManager)
            .getPositionInfo(
                key.toId(), address(vault), vault.positionLower(), vault.positionUpper(), vault.positionSalt()
            );
    }

    /// @notice Remove LP into vault custody, then reconcile the exact idle transfer to the Safe independently.
    function recoverPrincipal() internal returns (uint256 amountA, uint256 amountB) {
        uint256 beforeA = a.balanceOf(address(safe));
        uint256 beforeB = b.balanceOf(address(safe));
        uint256 totalA = a.balanceOf(draft.poolManager) + a.balanceOf(address(vault));
        uint256 totalB = b.balanceOf(draft.poolManager) + b.balanceOf(address(vault));
        require(coreLiquidity() > 0);
        safeCall(address(vault), abi.encodeCall(vault.exitLiquidity, ()), 0, 2);
        require(coreLiquidity() == 0 && vault.positionId() == 0);
        amountA = totalA - a.balanceOf(draft.poolManager);
        amountB = totalB - b.balanceOf(draft.poolManager);
        require(
            amountA > 0 && amountB > 0 && a.balanceOf(address(vault)) == amountA
                && b.balanceOf(address(vault)) == amountB
        );
        require(a.balanceOf(address(safe)) == beforeA && b.balanceOf(address(safe)) == beforeB);
        safeCall(address(vault), abi.encodeCall(vault.withdrawIdle, ()), 1, 2);
        require(a.balanceOf(address(safe)) == beforeA + amountA && b.balanceOf(address(safe)) == beforeB + amountB);
        require(a.balanceOf(address(vault)) == 0 && b.balanceOf(address(vault)) == 0);
    }
}
