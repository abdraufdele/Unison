// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeploymentConfig} from "./DeploymentConfig.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {CompensationEscrow} from "../../src/CompensationEscrow.sol";
import {ServiceHook} from "../../src/ServiceHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

abstract contract Bindings is DeploymentConfig {
    /// @notice Rebuild the fixed-fee C1 pool key from the ordered currencies and installed hook.
    function poolKey(AgreementVault.Bindings memory b) internal pure returns (PoolKey memory) {
        return PoolKey(Currency.wrap(b.token0), Currency.wrap(b.token1), 3000, 60, IHooks(b.hook));
    }

    /// @notice Verify contract ownership, settlement recipients and core/hook/position identity without reading a price feed.
    function checkBindings(AgreementVault vault, Config memory c) internal view {
        AgreementVault.Terms memory t = vault.currentTerms();
        require(t.vault == address(vault) && t.chainId == block.chainid && t.agreementId == c.id, "agreement domain");
        require(
            t.treasury == c.treasury && t.manager == c.manager && t.treasuryRecipient == c.treasury
                && t.managerRecipient == c.manager,
            "fixed recipients"
        );
        AgreementVault.Bindings memory b = c.bindings;
        require(keccak256(abi.encode(t.bindings)) == keccak256(abi.encode(b)), "bindings changed");
        require(t.paymentToken == b.token1 && t.referenceBase == b.token0 && t.referenceQuote == b.token1, "currencies");
        require(uint160(b.hook) & 0x3fff == 0x840, "hook flags");
        require(
            b.hook.codehash == keccak256(vm.getDeployedCode("ServiceHook.sol:ServiceHook"))
                && b.escrow.codehash == keccak256(vm.getDeployedCode("CompensationEscrow.sol:CompensationEscrow")),
            "custody bytecode"
        );
        ServiceHook h = ServiceHook(b.hook);
        CompensationEscrow e = CompensationEscrow(b.escrow);
        require(
            h.vault() == address(vault) && address(h.poolManager()) == b.poolManager
                && PoolId.unwrap(h.poolId()) == PoolId.unwrap(poolKey(b).toId()),
            "hook binding"
        );
        require(
            e.vault() == address(vault) && address(e.paymentToken()) == b.token1 && e.treasuryRecipient() == c.treasury
                && e.managerRecipient() == c.manager,
            "escrow binding"
        );
        if (vault.positionLiquidity() != 0) {
            require(
                PoolId.unwrap(vault.positionPoolId()) == PoolId.unwrap(h.poolId())
                    && vault.positionId() == h.positionId(),
                "position identity"
            );
        }
    }
}
