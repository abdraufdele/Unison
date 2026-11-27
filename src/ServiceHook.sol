// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {ServiceRange} from "./ServiceRange.sol";

enum Operation {
    Seed,
    Add,
    Remove,
    Rerange,
    Exit
}

/// @notice C1 add-leg admission and cumulative qualifying service. Constructor-only bindings give every genuine instance the same runtime hash.
contract ServiceHook {
    using StateLibrary for IPoolManager;

    address public vault;
    IPoolManager public poolManager;
    PoolId public poolId;
    bytes32 public pendingAdd;

    uint8 public constant NOT_ACTIVATED = 1;
    uint8 public constant STOPPED = 2;
    uint8 public constant PERIOD_ENDED = 4;
    uint8 public constant NO_MATCHING_POSITION = 8;
    uint8 public constant BELOW_MINIMUM = 16;
    uint8 public constant BAND_NOT_COVERED = 32;
    uint8 public constant RANGE_NOT_PERMITTED = 64;
    uint8 public constant TICK_OUTSIDE = 128;

    uint256 public start;
    uint256 public scheduledEnd;
    uint256 public lastCheckpoint;
    uint256 public qualifyingSeconds;
    bool public stopped;
    bool public storedQualified;
    int24 public bandLower;
    int24 public bandUpper;
    int24 public positionLower;
    int24 public positionUpper;
    int24 public observedTick;
    uint128 public observedLiquidity;
    uint128 private installedLiquidity;
    bytes32 public positionSalt;

    error InvalidClockState();
    event ServiceCheckpoint(
        uint256 at,
        uint256 qualifyingSeconds,
        bool oldQualified,
        bool newQualified,
        bytes32 indexed positionId,
        int24 tick,
        uint128 liquidity
    );

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    error InvalidBinding();
    error NotVault();
    error WrongCoreOrPool();
    error InvalidAddContext();

    /// @notice Bind the sole vault and pool and require this address to enable exactly before-add and after-swap callbacks.
    constructor(address ownerVault, IPoolManager core, Currency token0, Currency token1) {
        if (
            ownerVault == address(0) || address(core) == address(0) || token0.isAddressZero() || token0 >= token1
                || (uint160(address(this)) & Hooks.ALL_HOOK_MASK)
                    != (Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG)
        ) {
            revert InvalidBinding();
        }
        vault = ownerVault;
        poolManager = core;
        poolId = PoolKey(token0, token1, 3000, 60, IHooks(address(this))).toId();
    }

    /// @dev The vault calls this inside its authenticated unlock, immediately before the single add leg.
    function armAdd(Operation kind, IPoolManager.ModifyLiquidityParams calldata params) external onlyVault {
        if (
            pendingAdd != 0 || params.liquidityDelta <= 0
                || (kind != Operation.Seed && kind != Operation.Add && kind != Operation.Rerange)
        ) revert InvalidAddContext();
        pendingAdd = keccak256(abi.encode(params, abi.encode(kind)));
    }

    /// @notice Consume the vault's exact add-leg grant after authenticating both the PoolManager and pool key.
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata leg
    ) external returns (bytes4) {
        authenticatePool(key);
        if (sender != vault) revert NotVault();
        if (pendingAdd == 0 || pendingAdd != keccak256(abi.encode(params, leg))) revert InvalidAddContext();
        delete pendingAdd;
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @notice Accrue using the old qualification before observing the new core state and returning zero hook delta.
    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        authenticatePool(key);
        checkpointInterval(true);
        return (IHooks.afterSwap.selector, 0);
    }

    /// @notice Start service once with the vault-confirmed seed identity, opening band and original scheduled end.
    function initializeClock(int24 lower, int24 upper, bytes32 salt, uint128 liquidity, uint256 end)
        external
        onlyVault
    {
        if (scheduledEnd != 0 || end <= block.timestamp) revert InvalidClockState();
        start = block.timestamp;
        scheduledEnd = end;
        bandLower = lower;
        bandUpper = upper;
        installObservation(lower, upper, salt, liquidity);
    }

    /// @notice Credit the pre-change state before the vault changes liquidity or retires the current salt.
    function beforeAdjustment() external onlyVault {
        checkpointInterval(false);
    }

    /// @dev Called once for the final, core-confirmed vault position, including an empty terminal exit.
    function installPosition(int24 lower, int24 upper, bytes32 salt, uint128 liquidity) external onlyVault {
        if (scheduledEnd == 0 || (stopped && liquidity != 0)) revert InvalidClockState();
        installObservation(lower, upper, salt, liquidity);
    }

    /// @notice Install the confirmed position, clear an empty salt and start its next interval at this timestamp.
    function installObservation(int24 lower, int24 upper, bytes32 salt, uint128 liquidity) private {
        positionLower = lower;
        positionUpper = upper;
        positionSalt = liquidity == 0 ? bytes32(0) : salt;
        installedLiquidity = liquidity;
        // Begin the next interval here. The vault credited the old one before changing liquidity.
        if (!stopped) {
            lastCheckpoint = block.timestamp;
            observePosition();
        } else {
            observedLiquidity = 0;
        }
        publishCheckpoint();
    }

    /// @notice Return the hash of pool, vault, ticks and salt, or zero when no position is installed.
    function positionId() public view returns (bytes32) {
        if (positionSalt == 0) return bytes32(0);
        return keccak256(abi.encode(poolId, vault, positionLower, positionUpper, positionSalt));
    }

    /// @notice Zero failure bits means qualifying now. Each set bit names a failed C1 predicate.
    function qualification() public view returns (bool qualified, uint8 failures) {
        if (scheduledEnd == 0) failures |= NOT_ACTIVATED;
        else if (block.timestamp >= scheduledEnd) failures |= PERIOD_ENDED;
        if (stopped) failures |= STOPPED;
        if (positionSalt == 0 || observedLiquidity == 0 || observedLiquidity != installedLiquidity) {
            failures |= NO_MATCHING_POSITION;
        }
        if (observedLiquidity < ServiceRange.MIN_LIQUIDITY) failures |= BELOW_MINIMUM;
        if (positionSalt == 0 || !ServiceRange.covers(positionLower, positionUpper, bandLower, bandUpper)) {
            failures |= BAND_NOT_COVERED;
        }
        if (positionSalt == 0 || !ServiceRange.permitted(positionLower, positionUpper, bandLower, bandUpper)) {
            failures |= RANGE_NOT_PERMITTED;
        }
        if (positionSalt == 0 || observedTick < positionLower || observedTick >= positionUpper) {
            failures |= TICK_OUTSIDE;
        }
        return (failures == 0, failures);
    }

    /// @notice Read the stored core tick and the liquidity attributed to this exact vault position.
    function observePosition() private {
        (, observedTick,,) = poolManager.getSlot0(poolId);
        observedLiquidity = positionSalt == 0
            ? 0
            : poolManager.getPositionLiquidity(
                poolId, Position.calculatePositionKey(vault, positionLower, positionUpper, positionSalt)
            );
    }

    /// @notice Return stored service seconds plus elapsed time on the old qualifying state through the scheduled end.
    function projectedSeconds() public view returns (uint256) {
        return storedQualified ? qualifyingSeconds + (clippedTime() - lastCheckpoint) : qualifyingSeconds;
    }

    /// @notice Cap the current block timestamp at the end accepted on activation.
    function clippedTime() private view returns (uint256) {
        return block.timestamp < scheduledEnd ? block.timestamp : scheduledEnd;
    }

    /// @notice Persist the open interval without mutating core or sampling a partially settled position.
    function checkpoint() external returns (uint256) {
        checkpointInterval(false);
        return qualifyingSeconds;
    }

    /// @notice Persist the open interval before refreshing price and liquidity after a swap, and stop on expiry.
    function checkpointInterval(bool observe) private {
        if (scheduledEnd == 0 || stopped) return;
        accrueInterval();
        if (lastCheckpoint == scheduledEnd) stopped = true;
        else if (observe) observePosition();
        publishCheckpoint();
    }

    /// @notice Persist the final clipped interval and freeze future service updates. Only the vault may stop early.
    function stopClock() external onlyVault {
        if (stopped) return;
        if (scheduledEnd == 0) revert InvalidClockState();
        accrueInterval();
        stopped = true;
        publishCheckpoint();
    }

    /// @notice Credit the projection before advancing its timestamp, preserving the old qualification.
    function accrueInterval() private {
        qualifyingSeconds = projectedSeconds();
        lastCheckpoint = clippedTime();
    }

    /// @notice Recompute failure predicates and emit the old and new qualifications with the observed position.
    function publishCheckpoint() private {
        bool old = storedQualified;
        (storedQualified,) = qualification();
        emit ServiceCheckpoint(
            lastCheckpoint, qualifyingSeconds, old, storedQualified, positionId(), observedTick, observedLiquidity
        );
    }

    /// @notice Require both the bound PoolManager caller and its complete accepted pool identity.
    function authenticatePool(PoolKey calldata key) private view {
        if (msg.sender != address(poolManager) || PoolId.unwrap(key.toId()) != PoolId.unwrap(poolId)) {
            revert WrongCoreOrPool();
        }
    }
}
