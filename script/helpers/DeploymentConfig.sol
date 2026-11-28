// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IC1Token} from "../../src/ExactToken.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {IOpeningReferenceAdapter} from "../../src/IOpeningReferenceAdapter.sol";
import {OpeningBand} from "../../src/OpeningBand.sol";

abstract contract DeploymentConfig is Script {
    struct Config {
        address treasury;
        address manager;
        bytes32 id;
        AgreementVault.Bindings bindings;
        uint160 price;
        bool fixture;
        bool faultDemo;
    }

    /// @notice Pin the official public core independently of user-editable JSON.
    function checkCore(uint256 chain, address core) internal view {
        if (chain == 31337) return;
        bool main = chain == 130;
        require(main || chain == 1301, "unsupported chain");
        require(
            core == (main ? 0x1F98400000000000000000000000000000000004 : 0x00B036B58a818B1BC34d502D3fE730Db729e62AC),
            "canonical core"
        );
        require(
            core.codehash
                == (main
                        ? bytes32(0x0092eba5db5c7b4a3adbeb5708998d71bd09ad0ab2c299e66ea3f39075e1d249)
                        : bytes32(0x7c5e10e0bd8580e13b48751e4cd7db6315577488d0f76b20bc6c8bcbe2646dc0)),
            "canonical core runtime"
        );
        IPoolManager(core).extsload(bytes32(0));
    }

    /// @notice Require an explicit chain confirmation whenever Forge prepares a public broadcast.
    function checkBroadcast() internal view {
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) && block.chainid != 31337) {
            require(vm.envUint("CONFIRM_CHAIN") == block.chainid, "broadcast chain confirmation");
        }
    }

    /// @notice Parse a named address from the selected JSON object.
    function dependency(string memory json, string memory key) internal pure returns (address target) {
        target = vm.parseJsonAddress(json, string.concat(".", key));
    }

    /// @notice Require actual bytecode at a reviewed address and match it to the configured hash.
    function reviewed(string memory json, string memory key) internal view returns (address target) {
        target = dependency(json, key);
        require(
            target.code.length > 0 && target.codehash == vm.parseJsonBytes32(json, string.concat(".", key, "Hash")),
            "dependency runtime"
        );
    }

    /// @notice Check the C1 denomination, quote direction, completeness, age and attainable opening band.
    function checkReference(AgreementVault.Bindings memory b) internal view returns (int24 lower, int24 upper) {
        require(
            b.token0 < b.token1 && IC1Token(b.token0).decimals() == 6 && IC1Token(b.token1).decimals() == 6,
            "C1 token order/units"
        );
        IOpeningReferenceAdapter.Observation memory o = IOpeningReferenceAdapter(b.referenceAdapter).observation();
        require(
            o.base == b.token0 && o.quote == b.token1 && o.source == b.referenceSource && o.baseDecimals == 6
                && o.quoteDecimals == 6 && o.feedDecimals == 8,
            "reference identity/units"
        );
        require(
            o.complete && o.answer > 0 && o.updatedAt > 0 && o.updatedAt <= block.timestamp
                && block.timestamp - o.updatedAt <= 60,
            "reference stale/incomplete"
        );
        return OpeningBand.calculate(uint256(o.answer), 60, 100, 480);
    }

    /// @notice Reject wrong chains, signer roles, missing production inputs and invalid prices before collecting transactions.
    function loadConfig(uint256 chain, string memory network) internal view returns (Config memory c) {
        string memory json = vm.readFile(vm.envOr("CONFIG", string.concat("config/", network, ".json")));
        require(
            block.chainid == chain && vm.parseJsonUint(json, ".chainId") == chain
                && keccak256(bytes(network)) == keccak256(bytes(vm.parseJsonString(json, ".network"))),
            "wrong network"
        );
        checkBroadcast();
        c.treasury = vm.envAddress("UNISON_TREASURY");
        c.manager = vm.envAddress("UNISON_MANAGER");
        c.id = vm.envBytes32("RUN_ID");
        require(
            msg.sender == c.treasury && c.treasury != address(0) && c.manager != address(0) && c.manager != c.treasury
                && c.id != 0,
            "deployment actor/run"
        );
        if (vm.keyExistsJson(json, ".treasury") || vm.keyExistsJson(json, ".manager")) {
            require(
                dependency(json, "treasury") == c.treasury && dependency(json, "manager") == c.manager,
                "configured parties"
            );
        }
        c.fixture = vm.parseJsonBool(json, ".fixtureAssets");
        c.faultDemo = vm.keyExistsJson(json, ".localFaultDemo") && vm.parseJsonBool(json, ".localFaultDemo");
        require(!c.faultDemo || (chain == 31337 && c.fixture), "local faults only");
        if (chain != 31337) {
            c.bindings.poolManager = reviewed(json, "core");
            checkCore(chain, c.bindings.poolManager);
        }
        if (c.fixture) {
            require(chain != 130, "mainnet prohibits fixtures");
            c.price = 1 << 96;
        } else {
            require(
                vm.keyExistsJson(json, ".token0") && vm.keyExistsJson(json, ".adapter"),
                "reviewed tokens and reference required"
            );
            require(
                chain != 130 || (vm.keyExistsJson(json, ".treasury") && vm.keyExistsJson(json, ".manager")),
                "reviewed parties required"
            );
            c.bindings.token0 = reviewed(json, "token0");
            c.bindings.token1 = reviewed(json, "token1");
            c.bindings.referenceAdapter = reviewed(json, "adapter");
            c.bindings.referenceSource = reviewed(json, "source");
            uint256 price = vm.parseJsonUint(json, ".initialSqrtPriceX96");
            require(price <= type(uint160).max, "price overflow");
            c.price = uint160(price);
            (int24 lo, int24 hi) = checkReference(c.bindings);
            int24 tick = TickMath.getTickAtSqrtPrice(c.price);
            require(tick >= lo && tick < hi, "seed outside band");
        }
    }
}
