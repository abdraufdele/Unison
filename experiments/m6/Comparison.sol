// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IC1Token, ExactToken, CustodyLock} from "../../src/ExactToken.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {ServiceHook} from "../../src/ServiceHook.sol";
import {ServiceRange} from "../../src/ServiceRange.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

/// @dev Dedicated measurement of CREATE2 deployment. Salt search runs offchain.
contract HookInstaller {
    function install(bytes32 salt, address vault, IPoolManager pm, Currency a, Currency b) external {
        new ServiceHook{salt: salt}(vault, pm, a, b);
    }
}

/// @dev Local exact-transfer fixture. Core is the only callback caller, and unlock calls are synchronous.
abstract contract CoreAccess {
    IPoolManager internal immutable core;

    constructor(IPoolManager manager) {
        core = manager;
    }

    function settle(Currency currency, int128 delta, address payer, address recipient) internal {
        IC1Token token = IC1Token(Currency.unwrap(currency));
        if (delta < 0) {
            uint256 due = uint128(-delta);
            core.sync(currency);
            if (payer == address(this)) ExactToken.pay(token, address(core), due);
            else ExactToken.pull(token, payer, address(core), due);
            require(core.settle() == due);
        } else if (delta > 0) {
            core.take(currency, recipient, uint128(delta));
        }
    }
}

/// @dev A shared local trader router and read-only measurement lens. Uses only the caller's swap allowance.
contract ComparisonRouter is CoreAccess {
    using StateLibrary for IPoolManager;

    constructor(IPoolManager manager) CoreAccess(manager) {}

    function order(PoolKey calldata key, bool sellA, uint256 offer, int24 limitTick) external {
        core.unlock(abi.encode(key, msg.sender, sellA, offer, limitTick));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(core));
        (PoolKey memory key, address trader, bool sellA, uint256 offer, int24 tick) =
            abi.decode(data, (PoolKey, address, bool, uint256, int24));
        BalanceDelta net =
            core.swap(key, IPoolManager.SwapParams(sellA, -int256(offer), TickMath.getSqrtPriceAtTick(tick)), "");
        settle(key.currency0, net.amount0(), trader, trader);
        settle(key.currency1, net.amount1(), trader, trader);
        return "";
    }

    function position(PoolKey calldata key, address owner, int24 lo, int24 hi, bytes32 salt)
        external
        view
        returns (
            uint160 sqrt,
            int24 tick,
            uint128 poolL,
            uint128 ownedL,
            uint256 feeA,
            uint256 feeB,
            uint256 growthA,
            uint256 growthB
        )
    {
        (sqrt, tick,,) = core.getSlot0(key.toId());
        poolL = core.getLiquidity(key.toId());
        (uint128 l, uint256 lastA, uint256 lastB) = core.getPositionInfo(key.toId(), owner, lo, hi, salt);
        ownedL = l;
        (uint256 insideA, uint256 insideB) = core.getFeeGrowthInside(key.toId(), lo, hi);
        unchecked {
            feeA = FullMath.mulDiv(insideA - lastA, l, 1 << 128);
            feeB = FullMath.mulDiv(insideB - lastB, l, 1 << 128);
        }
        (growthA, growthB) = core.getFeeGrowthGlobals(key.toId());
    }

    function price(int24 tick) external pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }
}

/// @dev Comparison-only LP with no hook and a single fixed pool. Each unlock binds its entire input.
abstract contract LocalPosition is CoreAccess, CustodyLock {
    using StateLibrary for IPoolManager;
    address internal immutable treasury;
    PoolKey internal key;
    int24 public edge = 120;
    uint128 public liquidity;
    uint256 public salt = 1;
    bytes32 private pending;
    uint128 internal constant SEED = 100_000_000_000;
    uint256 internal constant INVENTORY = 2_000_000_000;

    constructor(IPoolManager manager, address a, address b) CoreAccess(manager) {
        treasury = msg.sender;
        key = PoolKey(Currency.wrap(a), Currency.wrap(b), 3000, 60, IHooks(address(0)));
    }

    modifier onlyTreasury() {
        require(msg.sender == treasury);
        _;
    }

    function leg(int256 change, uint256 limitA, uint256 limitB, address wallet) internal {
        bytes memory data = abi.encode(change, limitA, limitB, wallet);
        pending = keccak256(data);
        core.unlock(data);
        require(pending == 0);
        liquidity = uint128(uint256(int256(uint256(liquidity)) + change));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(core) && pending == keccak256(data));
        delete pending;
        (int256 change, uint256 limitA, uint256 limitB, address wallet) =
            abi.decode(data, (int256, uint256, uint256, address));
        (BalanceDelta net, BalanceDelta fees) =
            core.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-edge, edge, change, bytes32(salt)), "");
        BalanceDelta principal = net - fees;
        checkLimit(principal.amount0(), change > 0, limitA);
        checkLimit(principal.amount1(), change > 0, limitB);
        settle(key.currency0, net.amount0(), wallet, wallet);
        settle(key.currency1, net.amount1(), wallet, wallet);
        return "";
    }

    function checkLimit(int128 amount, bool adding, uint256 limit) private pure {
        if (adding) {
            if (amount > 0 || uint256(-int256(amount)) > limit) revert AgreementVault.PrincipalLimit();
        } else if (amount < 0 || uint128(amount) < limit) {
            revert AgreementVault.PrincipalLimit();
        }
    }
}

/// @dev Owner keeps idle tokens in its wallet. One removal also delivers the position proceeds.
contract Passive is LocalPosition {
    constructor(IPoolManager manager, address a, address b) LocalPosition(manager, a, b) {}

    function seed() external onlyTreasury nonReentrant {
        require(liquidity == 0);
        leg(int256(uint256(SEED)), INVENTORY, INVENTORY, treasury);
    }

    function exit() external onlyTreasury nonReentrant {
        leg(-int256(uint256(liquidity)), 0, 0, treasury);
    }
}

interface IElapsed {
    function elapsed() external view returns (uint256 secondsDelivered, bool terminal);
}

/// @dev Separate funded custody. Non-reentrant independent pulls preserve accrued but unpaid rights.
contract RetainerEscrow is CustodyLock {
    IElapsed private immutable mandate;
    address private immutable treasury;
    address private immutable manager;
    IC1Token private immutable token;
    uint256 public claimed;
    uint256 public refunded;
    uint256 internal constant BUDGET = 100_000_000;

    constructor(address owner, address recipient, IC1Token payToken) {
        mandate = IElapsed(msg.sender);
        treasury = owner;
        manager = recipient;
        token = payToken;
    }

    function reserved() public view returns (uint256) {
        (uint256 elapsed,) = mandate.elapsed();
        return BUDGET * elapsed / 300 - claimed;
    }

    function claim() external nonReentrant {
        uint256 due = reserved();
        claimed += due;
        ExactToken.pay(token, manager, due);
    }

    function refund() external nonReentrant {
        (uint256 elapsed, bool terminal) = mandate.elapsed();
        require(terminal);
        uint256 due = BUDGET - BUDGET * elapsed / 300 - refunded;
        refunded += due;
        ExactToken.pay(token, treasury, due);
    }
}

/// @dev Immutable comparison mandate limited to the symmetric reranges in the workload.
contract Retainer is LocalPosition {
    using StateLibrary for IPoolManager;
    RetainerEscrow public immutable escrow;
    address private immutable manager;
    bytes32 public immutable termsHash;
    uint256 public start;
    uint256 private stopped;
    uint256 private last;
    bool private acceptedOwner;
    bool private acceptedManager;
    bool private funded;

    constructor(IPoolManager pm, address a, address b, address namedManager) LocalPosition(pm, a, b) {
        escrow = new RetainerEscrow(msg.sender, namedManager, IC1Token(b));
        manager = namedManager;
        termsHash = keccak256(abi.encode(block.chainid, address(this), msg.sender, namedManager, key, address(escrow)));
    }

    function accept(bytes32 h) external {
        require(h == termsHash);
        if (msg.sender == treasury) {
            acceptedOwner = true;
        } else {
            require(msg.sender == manager);
            acceptedManager = true;
        }
    }

    function fund(bytes32 h) external onlyTreasury nonReentrant {
        require(h == termsHash && acceptedOwner && acceptedManager && !funded);
        funded = true;
        ExactToken.pull(IC1Token(Currency.unwrap(key.currency0)), treasury, address(this), INVENTORY);
        ExactToken.pull(IC1Token(Currency.unwrap(key.currency1)), treasury, address(this), INVENTORY);
        ExactToken.pull(IC1Token(Currency.unwrap(key.currency1)), treasury, address(escrow), 100_000_000);
    }

    function activate(bytes32 h) external onlyTreasury nonReentrant {
        require(h == termsHash && funded && start == 0 && stopped == 0);
        (uint160 price,,,) = core.getSlot0(key.toId());
        require(price == 1 << 96);
        start = last = block.timestamp;
        leg(int256(uint256(SEED)), INVENTORY, INVENTORY, address(this));
    }

    function positionId() public view returns (bytes32) {
        return keccak256(abi.encode(key.toId(), address(this), -edge, edge, bytes32(salt)));
    }

    function rerange(bytes32 id, int24 lo, int24 hi, uint128 l, AgreementVault.Bounds calldata b)
        external
        nonReentrant
    {
        (uint256 elapsedSeconds, bool terminal) = elapsed();
        require(msg.sender == manager && elapsedSeconds > 0 && !terminal && block.timestamp >= last + 30);
        (uint128 actual,,) = core.getPositionInfo(key.toId(), address(this), -edge, edge, bytes32(salt));
        require(actual == liquidity && id == positionId() && b.termsHash == termsHash);
        require(b.validFrom <= block.timestamp && block.timestamp <= b.deadline && b.deadline - b.validFrom <= 30);
        (, int24 tick,,) = core.getSlot0(key.toId());
        require(b.tickLower >= -240 && b.tickUpper <= 240 && b.tickLower <= tick && tick < b.tickUpper);
        require(
            lo == -hi && hi != edge && ServiceRange.covers(lo, hi, -120, 120)
                && ServiceRange.permitted(lo, hi, -120, 120)
        );
        require(l > 0 && l <= 2 * SEED);
        leg(-int256(uint256(liquidity)), b.minOutput0, b.minOutput1, address(this));
        edge = hi;
        ++salt;
        leg(
            int256(uint256(l)),
            b.maxInput0 < INVENTORY ? b.maxInput0 : INVENTORY,
            b.maxInput1 < INVENTORY ? b.maxInput1 : INVENTORY,
            address(this)
        );
        last = block.timestamp;
    }

    function elapsed() public view returns (uint256, bool) {
        if (start == 0) return (0, stopped != 0);
        uint256 end = stopped != 0 ? stopped : start + 300;
        return block.timestamp >= end ? (end - start, true) : (block.timestamp - start, false);
    }

    function terminate() external onlyTreasury {
        require(funded && stopped == 0);
        if (start == 0) {
            stopped = block.timestamp;
            return;
        }
        stopped = block.timestamp < start + 300 ? block.timestamp : start + 300;
    }

    function exitLiquidity() external onlyTreasury nonReentrant {
        (, bool terminal) = elapsed();
        require(terminal);
        if (liquidity > 0) leg(-int256(uint256(liquidity)), 0, 0, address(this));
    }

    function withdrawIdle() external onlyTreasury nonReentrant {
        (, bool terminal) = elapsed();
        require(terminal);
        IC1Token a = IC1Token(Currency.unwrap(key.currency0));
        IC1Token b = IC1Token(Currency.unwrap(key.currency1));
        ExactToken.pay(a, treasury, a.balanceOf(address(this)));
        ExactToken.pay(b, treasury, b.balanceOf(address(this)));
    }
}
