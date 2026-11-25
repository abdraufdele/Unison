// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../src/AgreementVault.sol";
import {CompensationEscrow} from "../src/CompensationEscrow.sol";
import {ExactToken} from "../src/ExactToken.sol";
import {Operation} from "../src/ServiceHook.sol";
import {CustodyToken} from "./fixtures/CustodyFixture.sol";
import {PositionAccountingFixture} from "./fixtures/PositionAccountingFixture.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract CloseoutReconciliationTest is PositionAccountingFixture {
    using StateLibrary for IPoolManager;

    uint256 private constant START = 10_000;
    uint256 private constant END = START + 300;
    uint256 private time;
    uint256 private stop;
    uint256 private q;
    uint256 private paid;
    uint256 private returnedBudget;
    uint256 private budgetGifts;
    uint128 private liquidity;
    int24 private edge;
    uint256 private salt;
    uint256 private lastAdjustment;
    uint256 private positiveClaims;
    uint256 private positiveWithdrawals;

    struct Asset {
        uint256 spent;
        uint256 removed;
        uint256 fees;
        uint256 gifts;
        uint256 received;
    }
    Asset private assetA;
    Asset private assetB;

    event log_named_uint(string key, uint256 value);

    function _idle(Asset storage asset) private view returns (uint256) {
        return PRINCIPAL + asset.removed + asset.gifts + asset.fees - asset.spent - asset.received;
    }

    function _position() private view returns (uint128 actual) {
        (actual,,) = core.getPositionInfo(key.toId(), address(vault), -edge, edge, bytes32(salt));
    }

    function _id() private view returns (bytes32) {
        return
            liquidity == 0 ? bytes32(0) : keccak256(abi.encode(key.toId(), address(vault), -edge, edge, bytes32(salt)));
    }

    function _advance(uint256 next) private {
        require(next >= time);
        if (time < END && stop == 0) {
            (, int24 tick,,) = core.getSlot0(key.toId());
            // The generated identities are the seed or its permitted extension, both covering [-120,120).
            if (_position() >= SEED && tick >= -edge && tick < edge) q += (next < END ? next : END) - time;
        }
        time = next;
        vm.warp(next);
        _check();
    }

    function _check() private view {
        bool terminal = stop != 0 || time >= END;
        uint256 earned = BUDGET * q / 300;
        require(q <= 300 && paid <= earned && earned <= BUDGET && returnedBudget <= BUDGET - earned, "model limits");
        require(hook.projectedSeconds() == q && escrow.earned() == earned && escrow.fundedBudget() == BUDGET);
        require(vault.effectiveStop() == (stop != 0 ? stop : (time >= END ? END : 0)), "effective close");
        require(escrow.claimed() == paid && escrow.refunded() == returnedBudget);
        require(escrow.claimable() == earned - paid && escrow.reserved() == earned - paid);
        uint256 refund = terminal ? BUDGET - earned - returnedBudget : 0;
        uint256 accounted = BUDGET - paid - returnedBudget;
        require(escrow.refundable() == refund && escrow.accounted() == accounted);
        if (terminal) require(accounted == earned - paid + refund, "terminal conservation");
        require(b.balanceOf(address(escrow)) == accounted + budgetGifts && b.balanceOf(MANAGER) == paid);
        require(b.balanceOf(DONOR) == 0 && a.balanceOf(MANAGER) == 0);
        require(vault.positionId() == _id() && hook.positionId() == _id() && _position() == liquidity);
        require(vault.positionLiquidity() == liquidity && vault.positionSalt() == bytes32(salt));
        require(vault.lastAdjustment() == lastAdjustment && hook.pendingAdd() == 0, "authority/cooldown");
        require(
            a.balanceOf(address(vault)) == _idle(assetA) && b.balanceOf(address(vault)) == _idle(assetB), "idle assets"
        );
        require(
            a.balanceOf(address(this)) == assetA.received
                && b.balanceOf(address(this)) == assetB.received + returnedBudget,
            "fixed treasury"
        );
    }

    function _rollbackState() private view returns (bytes32) {
        (uint128 l, uint256 fa, uint256 fb) =
            core.getPositionInfo(key.toId(), address(vault), -edge, edge, bytes32(salt));
        return keccak256(
            abi.encode(
                l,
                fa,
                fb,
                core.getLiquidity(key.toId()),
                a.balanceOf(address(core)),
                b.balanceOf(address(core)),
                hook.qualifyingSeconds(),
                hook.lastCheckpoint(),
                hook.storedQualified(),
                hook.observedTick(),
                hook.observedLiquidity()
            )
        );
    }

    function _claim(bool blockFirst) private {
        uint256 target = BUDGET * q / 300;
        if (blockFirst) {
            require(target > paid);
            bytes32 beforeOp = _rollbackState();
            b.setFault(address(escrow), MANAGER, CustodyToken.Fault.Revert);
            vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
            escrow.claim();
            require(_rollbackState() == beforeOp);
            _check();
            b.setFault(address(escrow), MANAGER, CustodyToken.Fault.None);
        }
        vm.prank(DONOR);
        require(escrow.claim() == target - paid);
        if (target > paid) ++positiveClaims;
        paid = target;
        require(hook.qualifyingSeconds() == q);
    }

    function _refund() private {
        uint256 due = BUDGET - BUDGET * q / 300 - returnedBudget;
        require(due > 0);
        b.setFault(address(escrow), address(this), CustodyToken.Fault.FalseReturn);
        bytes32 beforeOp = _rollbackState();
        vm.expectRevert(abi.encodeWithSelector(ExactToken.TransferFailed.selector, address(b)));
        escrow.refund();
        require(_rollbackState() == beforeOp);
        _check();
        b.setFault(address(escrow), address(this), CustodyToken.Fault.None);
        vm.prank(DONOR);
        require(escrow.refund() == due);
        returnedBudget += due;
    }

    function _accountLeg(uint128 delta, bool adding) private {
        (uint256 amountA, uint256 amountB) = _principal(-edge, edge, delta, adding);
        if (liquidity != 0) {
            (uint256 feesA, uint256 feesB) = _fees(-edge, edge);
            assetA.fees += feesA;
            assetB.fees += feesB;
        }
        if (adding) {
            assetA.spent += amountA;
            assetB.spent += amountB;
            liquidity += delta;
        } else {
            assetA.removed += amountA;
            assetB.removed += amountB;
            liquidity -= delta;
        }
    }

    function _failedRerange(bytes32 id) private {
        AgreementVault.Bounds memory bad = _bounds();
        bad.maxInput0 = 0;
        bad.maxInput1 = 0;
        bytes32 beforeOp = _rollbackState();
        vm.expectRevert(AgreementVault.PrincipalLimit.selector);
        vm.prank(MANAGER);
        vault.rerange(id, -180, 180, SEED, bad);
        require(_rollbackState() == beforeOp);
        (uint128 proposed,,) = core.getPositionInfo(key.toId(), address(vault), -180, 180, bytes32(salt + 1));
        require(proposed == 0);
        _check();
        bytes memory leg = abi.encode(
            Operation.Rerange,
            IPoolManager.ModifyLiquidityParams(-180, 180, int256(uint256(SEED)), bytes32(salt + 1)),
            uint256(0),
            uint256(0)
        );
        vm.expectRevert(AgreementVault.InvalidOperation.selector);
        vm.prank(address(core));
        vault.unlockCallback(leg);
    }

    function _adjust(uint256 round) private {
        AgreementVault.Bounds memory bounds = _bounds();
        bytes32 id = _id();
        if (round == 0) {
            _accountLeg(SEED / 4, false);
            vm.prank(MANAGER);
            vault.remove(id, SEED / 4, bounds);
        } else if (round == 1) {
            _accountLeg(SEED / 4, true);
            vm.prank(MANAGER);
            vault.add(id, -edge, edge, SEED / 4, bounds);
        } else {
            _failedRerange(id);
            _accountLeg(liquidity, false);
            edge = 180;
            ++salt;
            _accountLeg(SEED, true);
            vm.prank(MANAGER);
            vault.rerange(id, -edge, edge, SEED, bounds);
            require(_liquidity(address(vault), bytes32(uint256(1))) == 0);
        }
        lastAdjustment = time;
        require(hook.qualifyingSeconds() == q);
    }

    function _withdraw() private {
        uint256 idleA = _idle(assetA);
        uint256 idleB = _idle(assetB);
        (uint256 gotA, uint256 gotB) = vault.withdrawIdle();
        require(gotA == idleA && gotB == idleB);
        if (gotA + gotB != 0) ++positiveWithdrawals;
        assetA.received += idleA;
        assetB.received += idleB;
    }

    function _deck(uint256 random) private pure returns (uint8[6] memory deck) {
        deck = [0, 1, 2, 3, 4, 5];
        for (uint256 n = 6; n > 1; --n) {
            uint256 index = random % n;
            (deck[n - 1], deck[index]) = (deck[index], deck[n - 1]);
            random /= n;
        }
    }

    function _activeAction(uint8 action, uint256 round, uint256 random) private {
        if (action == 0) {
            (, int24 tick,,) = core.getSlot0(key.toId());
            int24 magnitude = int24(uint24(15 + random % 151));
            _swap(tick <= 0 ? magnitude : -magnitude);
        } else if (action == 1) {
            _adjust(round);
        } else if (action == 2) {
            require(hook.checkpoint() == q);
        } else if (action == 3) {
            _claim(round == 0);
        } else if (action == 4) {
            uint256 gift = 1 + random % 500;
            _give(b, address(escrow), gift);
            budgetGifts += gift;
            _give(a, address(vault), gift);
            assetA.gifts += gift;
        } else {
            bytes32 beforeOp = _rollbackState();
            vm.expectRevert(CompensationEscrow.NotTerminal.selector);
            escrow.refund();
            AgreementVault.Bounds memory bounds = _bounds();
            vm.expectRevert(AgreementVault.PositionMismatch.selector);
            vm.prank(MANAGER);
            vault.remove(bytes32(0), SEED / 4, bounds);
            require(_rollbackState() == beforeOp);
        }
    }

    function _sequence(uint256 seed, bool early) private {
        for (uint256 round; round < 3; ++round) {
            uint256 random = uint256(keccak256(abi.encode(seed, round)));
            uint8[6] memory deck = _deck(random);
            for (uint256 i; i < 6; ++i) {
                random = uint256(keccak256(abi.encode(random, i)));
                _advance(START + 30 + 60 * round + 3 * i + random % 3);
                _activeAction(deck[i], round, random);
                _check();
            }
        }
        _advance(early ? START + 185 + seed % 85 : END);
        if (early) {
            vault.terminate();
            stop = time;
        }
        _check();
        uint8[6] memory closeOrder = _deck(uint256(keccak256(abi.encode(seed, "close"))));
        for (uint256 i; i < 6; ++i) {
            _advance(time + i);
            uint8 action = closeOrder[i];
            if (action == 0) {
                _claim(false);
            } else if (action == 1) {
                _refund();
            } else if (action == 2) {
                _withdraw();
            } else if (action == 3) {
                require(liquidity == SEED);
                _accountLeg(liquidity, false);
                vault.exitLiquidity();
            } else if (action == 4) {
                _swap(191);
            } else {
                require(hook.checkpoint() == q);
            }
            _check();
        }
        _withdraw();
        if (!early) {
            require(vault.recordedStop() == 0);
            vault.finalizeExpiry();
        }
        vault.terminate();
        vault.exitLiquidity();
        require(escrow.claim() == 0 && escrow.refund() == 0);
        _check();
        require(positiveClaims > 0 && positiveWithdrawals > 0 && returnedBudget > 0 && liquidity == 0);
        require(assetA.fees + assetB.fees > 0 && hook.qualifyingSeconds() == q);
    }

    // Split the fixed corpus across test transactions to stay inside the normal gas limit.
    function testCloseoutSeeds00To07() public {
        _corpus(0);
    }

    function testCloseoutSeeds08To15() public {
        _corpus(8);
    }

    function testCloseoutSeeds16To23() public {
        _corpus(16);
    }

    function testCloseoutSeeds24To31() public {
        _corpus(24);
    }

    function _corpus(uint256 first) private {
        _active();
        time = START;
        edge = 120;
        salt = 1;
        liquidity = SEED;
        assetA.spent = COST;
        assetB.spent = COST;
        uint256 claims;
        uint256 withdrawals;
        for (uint256 i = first; i < first + 8; ++i) {
            uint256 snapshot = vm.snapshotState();
            _sequence(uint256(keccak256(abi.encode(uint256(0x19112026), i))), i % 2 == 0);
            claims += positiveClaims;
            withdrawals += positiveWithdrawals;
            require(vm.revertToStateAndDelete(snapshot));
        }
        emit log_named_uint("positive manager claims", claims);
        emit log_named_uint("positive principal withdrawals", withdrawals);
    }
}
