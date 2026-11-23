// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Deliberately small local experiment. Not a production agreement or audited vault.
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

contract MockToken {
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

abstract contract Settler is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    IPoolManager public immutable core;
    bool internal executing;
    constructor(IPoolManager c) { core = c; }
    function settle(PoolKey memory key, BalanceDelta delta) internal {
        settleCurrency(key.currency0, delta.amount0());
        settleCurrency(key.currency1, delta.amount1());
    }
    function settleCurrency(Currency currency, int128 amount) internal {
        if (amount < 0) {
            core.sync(currency);
            require(MockToken(Currency.unwrap(currency)).transfer(address(core), uint128(-amount)));
            core.settle();
        } else if (amount > 0) {
            core.take(currency, address(this), uint128(amount));
        }
    }
}

contract ExperimentVault is Settler {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    address public immutable treasury;
    address public immutable manager;
    MockToken public immutable token0;
    MockToken public immutable token1;
    ServiceHook public hook;
    PoolKey internal key;
    int24 public lower = -120;
    int24 public upper = 120;
    bytes32 public salt;
    bool public bound;
    bool public revoked;
    bool internal pending;

    constructor(IPoolManager c, address t, address m, MockToken a, MockToken b) Settler(c) {
        treasury = t; manager = m; token0 = a; token1 = b;
    }
    function bind(ServiceHook h) external {
        require(msg.sender == treasury && !bound);
        hook = h; bound = true;
        key = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, 60, IHooks(address(h)));
    }
    function poolKey() external view returns (PoolKey memory) { return key; }
    function positionLiquidity() public view returns (uint128 l) {
        (l,,) = core.getPositionInfo(key.toId(), address(this), lower, upper, salt);
    }
    function currentTick() public view returns (int24 tick) { (,tick,,) = core.getSlot0(key.toId()); }
    function change(int256 delta) external {
        require(msg.sender == treasury || (msg.sender == manager && !revoked));
        require(!executing && bound);
        beforeChange();
        executing = true; pending = true;
        core.unlock(abi.encode(false, delta, lower, upper));
        executing = false; pending = false;
        afterChange();
    }
    function rerange(int24 lo, int24 hi, uint128 newLiquidity) external {
        require(msg.sender == treasury || (msg.sender == manager && !revoked));
        require(!executing && lo >= -600 && hi <= 600 && lo < hi && lo % 60 == 0 && hi % 60 == 0);
        beforeChange();
        executing = true; pending = true;
        core.unlock(abi.encode(true, int256(uint256(newLiquidity)), lo, hi));
        executing = false; pending = false;
        afterChange();
    }
    function beforeChange() internal {
        if (address(hook) != address(0)) hook.checkpoint(); // MUTATION_TARGET
    }
    function afterChange() internal {
        if (address(hook) != address(0)) hook.refresh();
    }
    function allowedPosition(int24 lo, int24 hi, bytes32 s) external view returns (bool) {
        return executing && pending && lo == lower && hi == upper && s == salt;
    }
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(core) && executing);
        (bool move, int256 delta, int24 lo, int24 hi) = abi.decode(data, (bool,int256,int24,int24));
        if (move) {
            uint128 l = positionLiquidity();
            if (l > 0) modify(-int256(uint256(l)));
            lower = lo; upper = hi; salt = bytes32(uint256(salt) + 1);
        }
        modify(delta);
        return "";
    }
    function modify(int256 delta) internal {
        (BalanceDelta d,) = core.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(lower,upper,delta,salt), "");
        settle(key,d);
    }
    function terminate() external {
        require(msg.sender == treasury);
        revoked = true;
        if (address(hook) != address(0)) hook.terminate();
    }
    function withdrawIdle() external {
        require(msg.sender == treasury && revoked && !executing);
        token0.transfer(treasury, token0.balanceOf(address(this)));
        token1.transfer(treasury, token1.balanceOf(address(this)));
    }
}

contract ServiceHook {
    using PoolIdLibrary for PoolKey;
    IPoolManager public immutable core;
    ExperimentVault public immutable vault;
    uint128 public constant MIN_LIQUIDITY = 1e15;
    bool public active;
    bool public stopped;
    bool public qualified;
    uint256 public start;
    uint256 public end;
    uint256 public last;
    uint256 public qualifyingSeconds;
    uint256 public swapCallbacks;
    PoolId public poolId;
    event Observation(uint256 time, bool qualified, uint256 secondsEarned);

    constructor(IPoolManager c, ExperimentVault v) {
        core = c; vault = v;
        // Real CREATE2 deployment must carry exactly beforeAddLiquidity + afterSwap.
        require((uint160(address(this)) & Hooks.ALL_HOOK_MASK) == (Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG));
    }
    function activate() external {
        require(msg.sender == vault.treasury() && !active && !stopped);
        require(!vault.revoked());
        poolId = vault.poolKey().toId();
        start = block.timestamp; end = start + 300; last = start; active = true;
        qualified = actualQualification();
        require(qualified);
    }
    function actualQualification() public view returns (bool) {
        int24 tick = vault.currentTick();
        return vault.positionLiquidity() >= MIN_LIQUIDITY
            && vault.lower() <= -60 && vault.upper() >= 60
            && tick >= vault.lower() && tick < vault.upper();
    }
    function checkpoint() external {
        // Permissionless: callers cannot supply state, timestamps or recipients.
        accrue();
    }
    function refresh() external {
        require(msg.sender == address(vault));
        // Caller MUST checkpoint old state before changing liquidity.
        if (active && !stopped) qualified = actualQualification();
        emit Observation(block.timestamp, qualified, qualifyingSeconds);
    }
    function accrue() internal {
        if (!active || stopped) return;
        uint256 nowClipped = block.timestamp < end ? block.timestamp : end;
        if (qualified) qualifyingSeconds += nowClipped - last;
        last = nowClipped;
    }
    function secondsNow() public view returns (uint256 q) {
        q = qualifyingSeconds;
        if (active && !stopped && qualified) {
            uint256 nowClipped = block.timestamp < end ? block.timestamp : end;
            q += nowClipped - last;
        }
    }
    function terminate() external {
        require(msg.sender == address(vault));
        accrue(); stopped = true; qualified = false;
    }
    function beforeAddLiquidity(address sender, PoolKey calldata k, IPoolManager.ModifyLiquidityParams calldata p, bytes calldata)
        external view returns (bytes4)
    {
        require(msg.sender == address(core));
        require(PoolId.unwrap(k.toId()) == PoolId.unwrap(vault.poolKey().toId()));
        require(sender == address(vault) && vault.allowedPosition(p.tickLower,p.tickUpper,p.salt));
        return IHooks.beforeAddLiquidity.selector;
    }
    function afterSwap(address, PoolKey calldata k, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external returns (bytes4,int128)
    {
        require(msg.sender == address(core));
        require(PoolId.unwrap(k.toId()) == PoolId.unwrap(vault.poolKey().toId()));
        swapCallbacks++;
        if (active && !stopped) { accrue(); qualified = actualQualification(); }
        emit Observation(block.timestamp, qualified, qualifyingSeconds);
        return (IHooks.afterSwap.selector,0);
    }
}

contract Compensation {
    MockToken public immutable token;
    ServiceHook public immutable ledger;
    address public immutable beneficiary;
    uint256 public constant CAP = 300e18;
    uint256 public paid;
    constructor(MockToken p, ServiceHook h, address m) { token = p; ledger = h; beneficiary = m; }
    function earned() public view returns (uint256) {
        uint256 amount = ledger.secondsNow() * 1e18;
        return amount < CAP ? amount : CAP;
    }
    function claim() external {
        ledger.checkpoint();
        uint256 amount = earned() - paid;
        paid += amount;
        require(token.transfer(beneficiary,amount));
    }
}

// Own inventory, no approvals, no external route selection. Two instances test independent routers.
contract LocalRouter is Settler {
    PoolKey internal key;
    address public immutable trader;
    constructor(IPoolManager c, PoolKey memory k, address t) Settler(c) { key=k; trader=t; }
    function tradeTo(int24 target) external {
        require(msg.sender == trader && !executing);
        executing = true;
        core.unlock(abi.encode(target));
        executing = false;
    }
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(core) && executing);
        int24 target = abi.decode(data,(int24));
        (uint160 currentPrice,,,) = StateLibrary.getSlot0(core,key.toId());
        uint160 targetPrice = priceAt(target);
        require(targetPrice != currentPrice, "same price");
        bool down = targetPrice < currentPrice;
        BalanceDelta d = core.swap(key, IPoolManager.SwapParams(down,-int256(1e24),targetPrice), "");
        settle(key,d);
        return "";
    }
    function priceAt(int24 tick) internal pure returns (uint160) { return TickMath.getSqrtPriceAtTick(tick); }
    using PoolIdLibrary for PoolKey;
}
