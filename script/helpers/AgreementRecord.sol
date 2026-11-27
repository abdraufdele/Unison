// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Bindings} from "./Bindings.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {ServiceHook} from "../../src/ServiceHook.sol";
import {CompensationEscrow} from "../../src/CompensationEscrow.sol";

abstract contract AgreementRecord is Bindings {
    struct Agreement {
        AgreementVault vault;
        AgreementVault.Terms terms;
        ServiceHook hook;
        CompensationEscrow escrow;
        bytes32 hash;
        bytes32 position;
        AgreementVault.State state;
    }

    /// @notice Compare a recorded runtime fingerprint with code on the selected chain.
    function recordedAddress(string memory json, string memory role) internal view returns (address target) {
        target = dependency(json, string.concat("addresses.", role));
        require(
            target.code.length != 0
                && target.codehash == vm.parseJsonBytes32(json, string.concat(".runtime.", role, ".keccak256")),
            "recorded runtime changed"
        );
    }

    /// @notice Authenticate the mined v1 record, endpoint, CREATE2 constructor, role bindings and live position.
    function agreement() internal view returns (Agreement memory a) {
        string memory json = vm.readFile(vm.envString("MANIFEST"));
        require(
            keccak256(bytes(vm.parseJsonString(json, ".schema"))) == keccak256("unison.deployment.v1")
                && keccak256(bytes(vm.parseJsonString(json, ".status"))) == keccak256("complete"),
            "incomplete deployment"
        );
        bytes32 mode = keccak256(bytes(vm.parseJsonString(json, ".mode")));
        require(
            mode == keccak256("local") || mode == keccak256("broadcast") || mode == keccak256("fork-rehearsal"),
            "unmined deployment"
        );
        require(vm.parseJsonUint(json, ".chainId") == block.chainid, "manifest chain");
        require(
            vm.parseBytes32(string.concat("0x", vm.parseJsonString(json, ".endpointId")))
                == sha256(bytes(vm.envString("UNISON_SCRIPT_RPC"))),
            "manifest endpoint"
        );
        Config memory c;
        c.id = vm.envBytes32("RUN_ID");
        require(c.id == vm.parseJsonBytes32(json, ".runId"), "wrong run");
        c.treasury = dependency(json, "treasury");
        c.manager = dependency(json, "manager");
        a.vault = AgreementVault(recordedAddress(json, "vault"));
        a.terms = a.vault.currentTerms();
        c.bindings = a.terms.bindings;
        c.bindings.poolManager = recordedAddress(json, "core");
        checkCore(block.chainid, c.bindings.poolManager);
        c.bindings.token0 = recordedAddress(json, "token0");
        c.bindings.token1 = recordedAddress(json, "token1");
        c.bindings.hook = recordedAddress(json, "hook");
        c.bindings.escrow = recordedAddress(json, "escrow");
        if (a.terms.revision == 2) {
            c.bindings.referenceAdapter = recordedAddress(json, "adapter");
            c.bindings.referenceSource = vm.keyExistsJson(json, ".referenceSource")
                ? dependency(json, "referenceSource")
                : c.bindings.referenceAdapter;
            require(a.vault.termsHash() == vm.parseJsonBytes32(json, ".termsHash"), "deployment terms");
        }
        bytes32 init = keccak256(
            bytes.concat(
                vm.getCode("ServiceHook.sol:ServiceHook"),
                abi.encode(a.vault, c.bindings.poolManager, c.bindings.token0, c.bindings.token1)
            )
        );
        address factory = recordedAddress(json, "factory");
        require(
            vm.computeCreate2Address(vm.parseJsonBytes32(json, ".create2.salt"), init, factory) == c.bindings.hook
                && init == vm.parseJsonBytes32(json, ".create2.initHash"),
            "CREATE2 identity"
        );
        require(
            factory == dependency(json, "create2.factory") && c.bindings.hook == dependency(json, "create2.address")
                && keccak256(bytes(vm.parseJsonString(json, ".create2.flags"))) == keccak256("0x840"),
            "recorded hook flags/plan"
        );
        require(vm.computeCreateAddress(address(a.vault), 1) == recordedAddress(json, "quote"), "quote identity");
        checkBindings(a.vault, c);
        a.hook = ServiceHook(c.bindings.hook);
        a.escrow = CompensationEscrow(c.bindings.escrow);
        a.position = a.vault.positionId();
        a.hash = a.vault.termsHash();
        a.state = a.vault.state();
    }

    /// @notice Bind this one operation to an explicit signer and operator-reviewed snapshot before simulating its call.
    function action() internal view returns (Agreement memory a) {
        checkBroadcast();
        a = agreement();
        require(
            msg.sender == vm.envAddress("ACTOR") && (msg.sender == a.terms.treasury || msg.sender == a.terms.manager),
            "wrong actor"
        );
        require(a.hash == vm.envBytes32("TERMS") && a.position == vm.envBytes32("POSITION"), "stale terms/position");
        require(uint256(a.state) == vm.envUint("EXPECTED_STATE"), "stale state");
        require(block.timestamp <= vm.envUint("DEADLINE"), "operator deadline");
    }
}
