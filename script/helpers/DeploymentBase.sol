// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Bindings} from "./Bindings.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {OpeningQuote} from "../../src/OpeningQuote.sol";
import {SeedPool} from "../../src/SeedPool.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

interface IHookInstaller {
    /// @notice Create the compiled ServiceHook with the mined salt and exact constructor tuple.
    function install(bytes32 salt, address vault, IPoolManager manager, Currency a, Currency b) external;
}

interface ILocalFaultToken {
    /// @notice Supply disposable inventory only for the explicitly selected local fault experiment.
    function mint(address recipient, uint256 amount) external;
}

abstract contract DeploymentBase is Bindings {
    /// @notice Use direct CREATE with the active treasury signer and record exact artifact inputs.
    function createContract(string memory role, string memory artifact, bytes memory arguments)
        internal
        returns (address deployed)
    {
        bytes memory init = bytes.concat(vm.getCode(artifact), arguments);
        assembly ("memory-safe") { deployed := create(0, add(init, 32), mload(init)) }
        require(deployed.code.length != 0, "treasury CREATE failed");
        record(role, artifact, arguments, deployed);
    }

    /// @notice Retain both constructor input and observed simulation code identity for manifest reconciliation.
    function record(string memory role, string memory artifact, bytes memory arguments, address deployed) internal {
        vm.serializeString("recipe", "addresses", vm.serializeAddress("addresses", role, deployed));
        vm.serializeString("recipe", "artifacts", vm.serializeString("artifacts", role, artifact));
        vm.serializeString("recipe", "arguments", vm.serializeBytes("arguments", role, arguments));
        vm.serializeString("recipe", "hashes", vm.serializeBytes32("hashes", role, deployed.codehash));
    }

    /// @notice Mine against a single reusable CREATE2 preimage buffer without allocating per candidate.
    function mineSalt(address factory, bytes32 initHash) internal view returns (bytes32 salt, address hook) {
        bytes memory input = abi.encodePacked(bytes1(0xff), factory, bytes32(0), initHash);
        for (uint256 i; i < 1_000_000; ++i) {
            assembly ("memory-safe") {
                mstore(add(input, 53), i)
                hook := and(keccak256(add(input, 32), 85), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            if ((uint160(hook) & 0x3fff) == 0x840 && hook.code.length == 0) return (bytes32(i), hook);
        }
        revert("salt search exhausted");
    }

    /// @notice Resolve external or demo currencies, order the latter and bind the fixture's source.
    function setupDependencies(Config memory c) internal {
        AgreementVault.Bindings memory b = c.bindings;
        if (block.chainid == 31337) {
            b.poolManager = createContract("core", "PoolManager.sol:PoolManager", abi.encode(c.treasury));
        }
        if (c.fixture) {
            string memory token = c.faultDemo ? "CustodyFixture.sol:CustodyToken" : "DemoAssets.sol:DemoToken";
            // Determine role labels before recording direct creations.
            address first = vm.computeCreateAddress(c.treasury, vm.getNonce(c.treasury));
            address second = vm.computeCreateAddress(c.treasury, vm.getNonce(c.treasury) + 1);
            require(createContract(first < second ? "token0" : "token1", token, "") == first, "first token nonce");
            require(createContract(first < second ? "token1" : "token0", token, "") == second, "second token nonce");
            (b.token0, b.token1) = first < second ? (first, second) : (second, first);
            b.referenceAdapter =
                createContract("adapter", "DemoAssets.sol:DemoReference", abi.encode(b.token0, b.token1));
            b.referenceSource = b.referenceAdapter;
            if (c.faultDemo) {
                ILocalFaultToken(b.token0).mint(c.treasury, 10_000_000_000);
                ILocalFaultToken(b.token1).mint(c.treasury, 10_000_000_000);
            }
        }
    }

    /// @notice Deploy as treasury, install final custody through revise, initialize the C1 pool and export a simulation recipe.
    function deploy(uint256 chain, string memory network) internal {
        Config memory c = loadConfig(chain, network);
        string memory path = vm.envString("UNISON_RECIPE");
        require(!vm.exists(path), "deployment recipe exists");
        vm.startBroadcast(c.treasury);
        setupDependencies(c);
        AgreementVault.Bindings memory b = c.bindings;
        address factory = createContract("factory", "Comparison.sol:HookInstaller", "");
        b.hook = address(uint160(uint256(keccak256(abi.encode(c.id, "draft hook")))));
        b.escrow = address(uint160(uint256(keccak256(abi.encode(c.id, "draft escrow")))));
        require(b.hook.code.length == 0 && b.escrow.code.length == 0, "occupied placeholders");
        AgreementVault v = AgreementVault(
            createContract("vault", "AgreementVault.sol:AgreementVault", abi.encode(c.id, c.manager, b))
        );
        address quote = vm.computeCreateAddress(address(v), 1);
        require(quote.codehash == keccak256(vm.getDeployedCode("OpeningQuote.sol:OpeningQuote")), "constructor quote");
        record("quote", "OpeningQuote.sol:OpeningQuote", "", quote);
        b.escrow = createContract(
            "escrow", "CompensationEscrow.sol:CompensationEscrow", abi.encode(v, b.token1, c.treasury, c.manager)
        );
        installHook(factory, v, b);
        v.revise(b);
        IPoolManager(b.poolManager).initialize(poolKey(b), c.price);
        vm.stopBroadcast();
        verifyDraft(v, c);
        vm.serializeString("recipe", "addresses", vm.serializeAddress("addresses", "core", b.poolManager));
        vm.serializeBytes32("hashes", "token0", b.token0.codehash);
        vm.serializeBytes32("hashes", "token1", b.token1.codehash);
        vm.serializeBytes32("hashes", "adapter", b.referenceAdapter.codehash);
        vm.serializeBytes32("hashes", "source", b.referenceSource.codehash);
        vm.serializeString("recipe", "hashes", vm.serializeBytes32("hashes", "core", b.poolManager.codehash));
        vm.serializeAddress("recipe", "token0", b.token0);
        vm.serializeAddress("recipe", "token1", b.token1);
        vm.serializeAddress("recipe", "adapter", b.referenceAdapter);
        vm.serializeAddress("recipe", "source", b.referenceSource);
        vm.writeJson(vm.serializeBytes32("recipe", "simulatedTerms", v.termsHash()), path);
    }

    /// @notice Install the unique hook through the factory using the compiled constructor bytes.
    function installHook(address factory, AgreementVault v, AgreementVault.Bindings memory b) internal {
        bytes memory args = abi.encode(v, b.poolManager, b.token0, b.token1);
        bytes32 initHash = keccak256(bytes.concat(vm.getCode("ServiceHook.sol:ServiceHook"), args));
        (bytes32 salt, address hook) = mineSalt(factory, initHash);
        b.hook = hook;
        IHookInstaller(factory)
            .install(salt, address(v), IPoolManager(b.poolManager), Currency.wrap(b.token0), Currency.wrap(b.token1));
        record("hook", "ServiceHook.sol:ServiceHook", args, hook);
        vm.serializeBytes32("recipe", "salt", salt);
        vm.serializeBytes32("recipe", "initHash", initHash);
    }

    /// @notice Verify actual draft custody and seed feasibility before exporting the plan.
    function verifyDraft(AgreementVault v, Config memory c) internal view {
        AgreementVault.Bindings memory b = c.bindings;
        checkBindings(v, c);
        require(
            v.revision() == 2 && v.state() == AgreementVault.State.Draft && v.managerAcceptedRevision() == 0
                && v.treasuryAcceptedRevision() == 0 && v.positionId() == 0,
            "not a clean draft"
        );
        (int24 lo, int24 hi) = checkReference(b);
        SeedPool.Quote memory seed = OpeningQuote(vm.computeCreateAddress(address(v), 1))
            .seed(IPoolManager(b.poolManager), poolKey(b), lo, hi, v.currentTerms().parameters.seedLiquidity);
        require(
            seed.amount0 <= v.currentTerms().parameters.maxGrossInput0
                && seed.amount1 <= v.currentTerms().parameters.maxGrossInput1,
            "seed funding limit"
        );
    }
}
