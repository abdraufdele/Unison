// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompensationEscrow} from "./CompensationEscrow.sol";
import {CustodyLock, ExactToken, IC1Token} from "./ExactToken.sol";

import {IOpeningReferenceAdapter} from "./IOpeningReferenceAdapter.sol";
import {OpeningBand} from "./OpeningBand.sol";
import {OpeningQuote} from "./OpeningQuote.sol";
import {ServiceRange} from "./ServiceRange.sol";
import {SeedPool} from "./SeedPool.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

import {Operation, ServiceHook} from "./ServiceHook.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";

/// @notice C1 consent, principal custody and a single treasury-owned position.
contract AgreementVault is CustodyLock, IUnlockCallback {
    using StateLibrary for IPoolManager;
    enum State {
        Draft,
        Accepted,
        Funded,
        Cancelled,
        Active,
        Terminated,
        Expired
    }

    struct Bindings {
        address poolManager;
        address token0;
        address token1;
        address hook;
        address escrow;
        address referenceAdapter;
        address referenceSource;
    }

    struct Parameters {
        uint24 fee;
        int24 tickSpacing;
        uint8 token0Decimals;
        uint8 token1Decimals;
        uint256 inventory0;
        uint256 inventory1;
        uint256 budget;
        uint32 duration;
        uint8 referenceDecimals;
        uint32 maxReferenceAge;
        uint16 bandHalfWidthBps;
        uint128 seedLiquidity;
        uint128 minLiquidity;
        uint128 maxLiquidity;
        int24 maxWidthTicks;
        int24 maxEdgeExtensionTicks;
        uint256 maxGrossInput0;
        uint256 maxGrossInput1;
        uint32 adjustmentCooldown;
        uint32 maxExecutionWindow;
    }

    struct ActivationPreflight {
        IOpeningReferenceAdapter.Observation observation;
        int24 lower;
        int24 upper;
        SeedPool.Quote seed;
        uint256 available0;
        uint256 available1;
        uint256 escrowBalance;
    }

    struct Bounds {
        bytes32 termsHash;
        uint256 validFrom;
        uint256 deadline;
        int24 tickLower;
        int24 tickUpper;
        uint256 maxInput0;
        uint256 maxInput1;
        uint256 minOutput0;
        uint256 minOutput1;
    }

    struct Terms {
        uint256 chainId;
        address vault;
        bytes32 agreementId;
        uint256 revision;
        uint256 createdAt;
        uint256 activationCutoff;
        address treasury;
        address manager;
        address treasuryRecipient;
        address managerRecipient;
        Bindings bindings;
        address paymentToken;
        address referenceBase;
        address referenceQuote;
        Parameters parameters;
        bytes32 rulesVersion;
    }

    bytes32 public constant TERMS_SCHEMA = keccak256("Unison.AgreementVault.Terms.v1");
    bytes32 public constant RULES_VERSION = keccak256("Unison.C1.Rules.v1");

    OpeningQuote private immutable openingQuote = new OpeningQuote();

    // Compute the canonical runtime hashes at construction, outside the deployed vault code.
    bytes32 private immutable escrowCodeHash = keccak256(type(CompensationEscrow).runtimeCode);
    bytes32 private immutable hookCodeHash = keccak256(type(ServiceHook).runtimeCode);

    uint256 public immutable creationChainId;
    bytes32 public immutable agreementId;
    uint256 public immutable createdAt;
    uint256 public immutable activationCutoff;
    address public immutable treasury;
    address public immutable manager;

    Bindings private bindings;
    uint256 public revision;
    uint256 public treasuryAcceptedRevision;
    uint256 public managerAcceptedRevision;

    uint256 public fundedPrincipal0;
    uint256 public fundedPrincipal1;
    bool public cancelled;

    IOpeningReferenceAdapter.Observation public openingObservation;
    int24 public bandLower;
    int24 public bandUpper;
    uint256 public start;
    uint256 public scheduledEnd;
    uint256 public recordedStop;
    PoolId public positionPoolId;
    bytes32 public positionSalt;
    uint128 public positionLiquidity;
    int24 public positionLower;
    int24 public positionUpper;
    uint256 public lastAdjustment;
    bytes32 private pendingUnlock;

    error NotManager();
    error InvalidWindow();
    error AdjustmentCooldown();
    error ExecutionTick();
    error InvalidRange();
    error LiquidityLimit();
    error PrincipalLimit();

    event PositionAdjusted(
        Operation indexed kind,
        bytes32 indexed salt,
        int24 lower,
        int24 upper,
        uint128 liquidity,
        BalanceDelta principal,
        BalanceDelta fees
    );

    error AlreadyActivated();
    error InvalidPeriod();
    error InvalidServiceHook();
    error InvalidOperation();
    error PositionMismatch();
    error SettlementMismatch();
    error TermsClosed();
    error NotAccepted();
    error InvalidEscrow();
    error NotFunded();
    error WrongChain();
    error IncompleteFunding();
    error InsufficientCustody(address custodian, address token, uint256 available, uint256 required);
    error InvalidSeedLiquidity();
    error SeedInputLimit();
    error UnreadableReference();
    error ReferenceMismatch();
    error InvalidObservation();
    error InvalidDecimals(address token);
    error NotCancelled();
    error MissingAgreementId();
    error MissingAddress();
    error ConflictingIdentity(address identity);
    error UnsortedCurrencies();
    error NotTreasury();
    error NotParty();
    error CutoffReached();
    error WrongTermsHash(bytes32 expected, bytes32 current);

    event Activated(
        bytes32 indexed termsHash,
        PoolId indexed poolId,
        bytes32 indexed salt,
        int24 lower,
        int24 upper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        uint256 start,
        uint256 end
    );
    event OpeningFixed(int256 answer, uint256 observedAt, uint160 sqrtPriceX96, int24 tick);
    event PeriodClosed(State indexed reason, uint256 effectiveStop);
    event LiquidityExited(
        PoolId indexed poolId,
        bytes32 indexed salt,
        uint128 liquidity,
        int128 principal0,
        int128 principal1,
        int128 fees0,
        int128 fees1
    );

    event TermsPublished(uint256 indexed revision, bytes32 indexed termsHash);
    event PartyAccepted(uint256 indexed revision, bytes32 indexed termsHash, address indexed party);

    event Funded(
        uint256 indexed revision,
        bytes32 indexed termsHash,
        address indexed escrow,
        uint256 principal0,
        uint256 principal1,
        uint256 budget
    );
    event Cancelled(uint256 indexed revision, bytes32 indexed termsHash, address indexed caller);
    event IdleWithdrawn(address indexed recipient, uint256 amount0, uint256 amount1);

    /// @notice Fix the creating treasury, manager, creation chain and one-day cutoff before publishing revision one.
    constructor(bytes32 id, address namedManager, Bindings memory initialBindings) {
        if (id == bytes32(0)) revert MissingAgreementId();
        creationChainId = block.chainid;
        agreementId = id;
        createdAt = block.timestamp;
        activationCutoff = block.timestamp + 1 days;
        treasury = msg.sender;
        manager = namedManager;
        publishTerms(initialBindings);
    }

    /// @notice Replace draft bindings as the treasury. Publication clears both acceptance records.
    function revise(Bindings calldata next) external nonReentrant {
        if (msg.sender != treasury) revert NotTreasury();
        requireOpenTerms();
        publishTerms(next);
    }

    /// @notice Record the calling party's consent to this hash before the cutoff. Repeating consent is idempotent.
    function accept(bytes32 expectedHash) external nonReentrant {
        if (msg.sender != treasury && msg.sender != manager) revert NotParty();
        requireOpenTerms();
        checkHash(expectedHash);

        if (msg.sender == treasury) {
            if (treasuryAcceptedRevision == revision) return;
            treasuryAcceptedRevision = revision;
        } else {
            if (managerAcceptedRevision == revision) return;
            managerAcceptedRevision = revision;
        }
        emit PartyAccepted(revision, expectedHash, msg.sender);
    }

    /// @notice Reject a draft edit or consent once funding, cancellation or the activation cutoff closes the proposal.
    function requireOpenTerms() private view {
        if (cancelled || fundedPrincipal0 != 0) revert TermsClosed();
        if (block.timestamp >= activationCutoff) revert CutoffReached();
    }

    /// @notice Compare the caller's commitment with the current domain-separated terms hash.
    function checkHash(bytes32 expectedHash) private view {
        bytes32 current = termsHash();
        if (expectedHash != current) revert WrongTermsHash(expectedHash, current);
    }

    /// @notice Resolve the lifecycle from consent, custody and chain time, including expiry before finalization.
    function state() public view returns (State) {
        if (scheduledEnd != 0) {
            if (recordedStop != 0 && recordedStop < scheduledEnd) return State.Terminated;
            return block.timestamp >= scheduledEnd ? State.Expired : State.Active;
        }
        if (cancelled) return State.Cancelled;
        if (fundedPrincipal0 != 0) return State.Funded;
        if (treasuryAcceptedRevision == revision && managerAcceptedRevision == revision) return State.Accepted;
        return State.Draft;
    }

    /// @notice Pull the agreed principal and separate B budget, then reconcile every debit and receipt before crediting escrow.
    function fund(bytes32 expectedHash) external nonReentrant {
        if (msg.sender != treasury) revert NotTreasury();
        requireOpenTerms();
        checkHash(expectedHash);
        if (state() != State.Accepted) revert NotAccepted();

        CompensationEscrow escrow = checkedEscrow(0);
        Parameters memory p = c1Parameters();
        IC1Token token0 = IC1Token(bindings.token0);
        IC1Token token1 = IC1Token(bindings.token1);
        if (token0.decimals() != p.token0Decimals) revert InvalidDecimals(address(token0));
        if (token1.decimals() != p.token1Decimals) revert InvalidDecimals(address(token1));

        // Besides checking each leg, reconcile the whole call in case a later transfer changes an earlier balance.
        uint256 treasury0 = token0.balanceOf(treasury);
        uint256 treasury1 = token1.balanceOf(treasury);
        uint256 idle0 = token0.balanceOf(address(this));
        uint256 idle1 = token1.balanceOf(address(this));
        uint256 escrow1 = token1.balanceOf(address(escrow));

        ExactToken.pull(token0, treasury, address(this), p.inventory0);
        ExactToken.pull(token1, treasury, address(this), p.inventory1);
        ExactToken.pull(token1, treasury, address(escrow), p.budget);

        ExactToken.checkDebit(token0, treasury, treasury0, p.inventory0);
        ExactToken.checkDebit(token1, treasury, treasury1, p.inventory1 + p.budget);
        ExactToken.checkReceipt(token0, address(this), idle0, p.inventory0);
        ExactToken.checkReceipt(token1, address(this), idle1, p.inventory1);
        ExactToken.checkReceipt(token1, address(escrow), escrow1, p.budget);
        escrow.credit(p.budget);
        fundedPrincipal0 = p.inventory0;
        fundedPrincipal1 = p.inventory1;
        emit Funded(revision, expectedHash, address(escrow), p.inventory0, p.inventory1, p.budget);
    }

    /// @notice Require the canonical escrow runtime, fixed parties, token, vault and expected funded balance.
    function checkedEscrow(uint256 expectedBudget) private view returns (CompensationEscrow escrow) {
        escrow = CompensationEscrow(bindings.escrow);
        if (
            address(escrow).codehash != escrowCodeHash || escrow.vault() != address(this)
                || address(escrow.paymentToken()) != bindings.token1 || escrow.treasuryRecipient() != treasury
                || escrow.managerRecipient() != manager || escrow.fundedBudget() != expectedBudget
                || escrow.refunded() != 0
        ) revert InvalidEscrow();
    }

    /// @notice Close an unactivated agreement. Only the treasury may cancel before the cutoff.
    function cancel() external nonReentrant {
        if (scheduledEnd != 0) revert AlreadyActivated();
        if (msg.sender != treasury && block.timestamp < activationCutoff) revert NotTreasury();
        if (cancelled) return;
        cancelled = true;
        emit Cancelled(revision, termsHash(), msg.sender);
    }

    /// @notice Transfer both idle balances to the treasury after cancellation or close. Either failed leg reverts the call.
    function withdrawIdle() external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (msg.sender != treasury) revert NotTreasury();
        requirePrincipalExit();
        IC1Token token0 = IC1Token(bindings.token0);
        IC1Token token1 = IC1Token(bindings.token1);
        amount0 = token0.balanceOf(address(this));
        amount1 = token1.balanceOf(address(this));
        ExactToken.pay(token0, treasury, amount0);
        ExactToken.pay(token1, treasury, amount1);
        if (amount0 != 0 || amount1 != 0) emit IdleWithdrawn(treasury, amount0, amount1);
    }

    /// @notice Read the current accepted reference once. A preview neither fixes a band nor starts a period.
    function previewOpeningReference()
        public
        view
        returns (IOpeningReferenceAdapter.Observation memory observed, int24 lower, int24 upper)
    {
        State status = state();
        if (status != State.Accepted && status != State.Funded) revert NotAccepted();
        Parameters memory p = c1Parameters();
        (bool ok, bytes memory data) =
            bindings.referenceAdapter.staticcall(abi.encodeCall(IOpeningReferenceAdapter.observation, ()));
        if (!ok || data.length != 9 * 32) revert UnreadableReference();
        observed = abi.decode(data, (IOpeningReferenceAdapter.Observation));
        if (
            observed.source != bindings.referenceSource || observed.base != bindings.token0
                || observed.quote != bindings.token1 || observed.baseDecimals != p.token0Decimals
                || observed.quoteDecimals != p.token1Decimals || observed.feedDecimals != p.referenceDecimals
        ) {
            revert ReferenceMismatch();
        }
        if (IC1Token(observed.base).decimals() != p.token0Decimals) revert InvalidDecimals(observed.base);
        if (IC1Token(observed.quote).decimals() != p.token1Decimals) revert InvalidDecimals(observed.quote);
        if (
            !observed.complete || observed.answer <= 0 || observed.updatedAt == 0
                || observed.updatedAt > block.timestamp || block.timestamp - observed.updatedAt > p.maxReferenceAge
        ) revert InvalidObservation();
        // C1 normalization: answer * 10^6 / (10^8 * 10^6) = answer / 10^8, with no division loss.
        if (p.token0Decimals != 6 || p.token1Decimals != 6 || p.referenceDecimals != 8) {
            revert OpeningBand.UnsupportedParameters();
        }
        (lower, upper) = openingQuote.band(uint256(observed.answer), p.tickSpacing, p.bandHalfWidthBps, p.maxWidthTicks);
    }

    /// @notice Inspect feasibility at this instant. Activation must execute this check again before seeding.
    function preflightActivation(bytes32 expectedHash) public view returns (ActivationPreflight memory result) {
        if (state() != State.Funded) revert NotFunded();
        checkHash(expectedHash);
        if (block.chainid != creationChainId) revert WrongChain();
        if (treasuryAcceptedRevision != revision || managerAcceptedRevision != revision) revert NotAccepted();
        if (block.timestamp >= activationCutoff) revert CutoffReached();

        Parameters memory p = c1Parameters();
        if (fundedPrincipal0 != p.inventory0 || fundedPrincipal1 != p.inventory1) revert IncompleteFunding();
        CompensationEscrow escrow = checkedEscrow(p.budget);
        result.escrowBalance = availableBalance(address(escrow), bindings.token1, p.budget);

        (result.observation, result.lower, result.upper) = previewOpeningReference();
        if (p.seedLiquidity == 0 || p.seedLiquidity < p.minLiquidity || p.seedLiquidity > p.maxLiquidity) {
            revert InvalidSeedLiquidity();
        }
        PoolKey memory key = poolKey();
        result.seed =
            openingQuote.seed(IPoolManager(bindings.poolManager), key, result.lower, result.upper, p.seedLiquidity);
        if (result.seed.amount0 > p.maxGrossInput0 || result.seed.amount1 > p.maxGrossInput1) revert SeedInputLimit();
        // Each actual vault balance must cover both the original mandate and its quoted seed leg.
        result.available0 = availableBalance(
            address(this), bindings.token0, p.inventory0 > result.seed.amount0 ? p.inventory0 : result.seed.amount0
        );
        result.available1 = availableBalance(
            address(this), bindings.token1, p.inventory1 > result.seed.amount1 ? p.inventory1 : result.seed.amount1
        );
    }

    /// @notice Reconstruct the full accepted core key with the fixed C1 fee and spacing.
    function poolKey() private view returns (PoolKey memory) {
        Parameters memory p = c1Parameters();
        return PoolKey(
            Currency.wrap(bindings.token0), Currency.wrap(bindings.token1), p.fee, p.tickSpacing, IHooks(bindings.hook)
        );
    }

    /// @notice Repeat funded preflight, settle the treasury seed, then initialize the service clock from the actual position.
    function activate(bytes32 expectedHash) external nonReentrant {
        if (msg.sender != treasury) revert NotTreasury();
        ActivationPreflight memory q = preflightActivation(expectedHash);
        ServiceHook hook = ServiceHook(bindings.hook);
        if (
            address(hook).codehash != hookCodeHash || hook.vault() != address(this)
                || hook.poolManager() != q.seed.manager || PoolId.unwrap(hook.poolId()) != PoolId.unwrap(q.seed.id)
                || hook.pendingAdd() != 0
        ) revert InvalidServiceHook();

        bandLower = q.lower;
        bandUpper = q.upper;
        positionPoolId = q.seed.id;
        openIdentity(q.lower, q.upper);
        (BalanceDelta net, BalanceDelta fees) =
            modifyPosition(Operation.Seed, int256(uint256(q.seed.liquidity)), q.seed.amount0, q.seed.amount1);
        if (
            BalanceDelta.unwrap(fees) != 0 || int256(net.amount0()) != -int256(q.seed.amount0)
                || int256(net.amount1()) != -int256(q.seed.amount1)
        ) revert SettlementMismatch();
        ExactToken.checkDebit(IC1Token(bindings.token0), address(this), q.available0, q.seed.amount0);
        ExactToken.checkDebit(IC1Token(bindings.token1), address(this), q.available1, q.seed.amount1);
        (uint160 sqrtPrice, int24 tick,,) = q.seed.manager.getSlot0(positionPoolId);
        if (
            sqrtPrice != q.seed.sqrtPriceX96 || tick != q.seed.tick
                || IC1Token(bindings.token1).balanceOf(bindings.escrow) != q.escrowBalance
        ) revert SettlementMismatch();
        openingObservation = q.observation;
        start = block.timestamp;
        scheduledEnd = start + c1Parameters().duration;
        hook.initializeClock(q.lower, q.upper, positionSalt, positionLiquidity, scheduledEnd);
        emit OpeningFixed(q.observation.answer, q.observation.updatedAt, sqrtPrice, tick);
        emit Activated(
            expectedHash,
            positionPoolId,
            positionSalt,
            bandLower,
            bandUpper,
            positionLiquidity,
            q.seed.amount0,
            q.seed.amount1,
            start,
            scheduledEnd
        );
    }

    /// @notice Zero denotes empty. The last salt stays visible after retirement.
    function positionId() public view returns (bytes32) {
        if (positionLiquidity == 0) return bytes32(0);
        return keccak256(abi.encode(positionPoolId, address(this), positionLower, positionUpper, positionSalt));
    }

    /// @notice Increase vault-owned liquidity inside the accepted range and the manager's gross input bounds.
    function add(bytes32 expectedId, int24 lower, int24 upper, uint128 liquidity, Bounds calldata bounds)
        external
        nonReentrant
    {
        beforeAdjustment(expectedId, bounds);
        if (positionLiquidity != 0 && (lower != positionLower || upper != positionUpper)) revert PositionMismatch();
        addLeg(Operation.Add, lower, upper, liquidity, bounds);
        afterAdjustment();
    }

    /// @notice Reduce the identified position subject to the manager's minimum principal outputs.
    function remove(bytes32 expectedId, uint128 liquidity, Bounds calldata bounds) external nonReentrant {
        beforeAdjustment(expectedId, bounds);
        removeLeg(Operation.Remove, liquidity, bounds);
        afterAdjustment();
    }

    /// @notice Remove the entire old identity and open another within both legs' bounds in one core transaction sequence.
    function rerange(bytes32 expectedId, int24 lower, int24 upper, uint128 liquidity, Bounds calldata bounds)
        external
        nonReentrant
    {
        beforeAdjustment(expectedId, bounds);
        if (lower == positionLower && upper == positionUpper) revert InvalidRange();
        removeLeg(Operation.Rerange, positionLiquidity, bounds);
        addLeg(Operation.Rerange, lower, upper, liquidity, bounds);
        afterAdjustment();
    }

    /// @notice Credit the pre-change state before the vault changes liquidity or retires the current salt.
    function beforeAdjustment(bytes32 expectedId, Bounds calldata b) private {
        if (msg.sender != manager) revert NotManager();
        if (state() != State.Active) revert InvalidPeriod();
        if (block.chainid != creationChainId) revert WrongChain();
        checkHash(b.termsHash);
        if (positionId() != expectedId || actualLiquidity() != positionLiquidity) revert PositionMismatch();
        Parameters memory p = c1Parameters();
        if (
            b.validFrom > block.timestamp || block.timestamp > b.deadline
                || b.deadline - b.validFrom > p.maxExecutionWindow
        ) revert InvalidWindow();
        uint256 previous = lastAdjustment == 0 ? start : lastAdjustment;
        if (block.timestamp < previous + p.adjustmentCooldown) revert AdjustmentCooldown();
        (, int24 tick,,) = IPoolManager(bindings.poolManager).getSlot0(positionPoolId);
        if (
            b.tickLower < bandLower - p.maxEdgeExtensionTicks || b.tickUpper > bandUpper + p.maxEdgeExtensionTicks
                || tick < b.tickLower || tick >= b.tickUpper
        ) revert ExecutionTick();
        ServiceHook(bindings.hook).beforeAdjustment();
    }

    /// @notice Publish the final core position to the clock before recording the successful adjustment time.
    function afterAdjustment() private {
        publishPosition();
        lastAdjustment = block.timestamp;
    }

    /// @notice Check C1 range and liquidity limits and apply the tighter of caller and mandate input caps.
    function addLeg(Operation kind, int24 lower, int24 upper, uint128 liquidity, Bounds calldata b) private {
        Parameters memory p = c1Parameters();
        if (
            !ServiceRange.covers(lower, upper, bandLower, bandUpper)
                || !ServiceRange.permitted(lower, upper, bandLower, bandUpper)
        ) revert InvalidRange();
        if (liquidity == 0 || uint256(positionLiquidity) + liquidity > p.maxLiquidity) revert LiquidityLimit();
        if (positionLiquidity == 0) openIdentity(lower, upper);
        modifyPosition(
            kind,
            int256(uint256(liquidity)),
            b.maxInput0 < p.maxGrossInput0 ? b.maxInput0 : p.maxGrossInput0,
            b.maxInput1 < p.maxGrossInput1 ? b.maxInput1 : p.maxGrossInput1
        );
    }

    /// @notice Require a nonzero removable quantity and settle with the caller's output floors.
    function removeLeg(Operation kind, uint128 liquidity, Bounds calldata b) private {
        if (liquidity == 0 || liquidity > positionLiquidity) revert LiquidityLimit();
        modifyPosition(kind, -int256(uint256(liquidity)), b.minOutput0, b.minOutput1);
    }

    /// @notice Advance the salt and require the new owner/ticks/salt key to have zero core liquidity.
    function openIdentity(int24 lower, int24 upper) private {
        positionSalt = bytes32(uint256(positionSalt) + 1);
        positionLower = lower;
        positionUpper = upper;
        if (actualLiquidity() != 0) revert PositionMismatch();
    }

    /// @notice Only a successfully activated agreement exposes its authenticated service hook.
    function settlementContext() external view returns (ServiceHook clock, uint256 duration, bool terminal) {
        if (scheduledEnd == 0) return (ServiceHook(address(0)), 0, cancelled);
        return (ServiceHook(bindings.hook), scheduledEnd - start, effectiveStop() != 0);
    }

    /// @notice Return the scheduled end on expiry or the recorded early stop, in chain seconds.
    function effectiveStop() public view returns (uint256) {
        return state() == State.Expired ? scheduledEnd : recordedStop;
    }

    /// @notice Let the treasury freeze service at the earlier of chain time and the original end.
    function terminate() external nonReentrant {
        if (msg.sender != treasury) revert NotTreasury();
        if (scheduledEnd == 0) revert InvalidPeriod();
        closePeriod(block.timestamp < scheduledEnd ? block.timestamp : scheduledEnd);
    }

    /// @notice Persist the scheduled stop once expiry is effective, independently of payments and removal.
    function finalizeExpiry() external nonReentrant {
        if (state() != State.Expired) revert InvalidPeriod();
        closePeriod(scheduledEnd);
    }

    /// @notice Stop the hook once and record the effective time before emitting the close reason.
    function closePeriod(uint256 stop) private {
        if (recordedStop != 0) return;
        ServiceHook(bindings.hook).stopClock();
        recordedStop = stop;
        emit PeriodClosed(state(), stop);
    }

    /// @notice Allow principal recovery only after cancellation, early termination or effective expiry.
    function requirePrincipalExit() private view {
        State status = state();
        if (status != State.Cancelled && status != State.Terminated && status != State.Expired) revert NotCancelled();
    }

    /// @notice Remove the full remaining core position into treasury custody without calling the escrow or reference.
    function exitLiquidity() external nonReentrant {
        if (msg.sender != treasury) revert NotTreasury();
        requirePrincipalExit();
        uint128 liquidity = positionLiquidity;
        if (liquidity == 0) return;
        ServiceHook(bindings.hook).stopClock();
        if (actualLiquidity() != liquidity) revert PositionMismatch();
        uint256 idle0 = IC1Token(bindings.token0).balanceOf(address(this));
        uint256 idle1 = IC1Token(bindings.token1).balanceOf(address(this));
        (BalanceDelta net, BalanceDelta fees) = modifyPosition(Operation.Exit, -int256(uint256(liquidity)), 0, 0);
        if (net.amount0() < 0 || net.amount1() < 0) revert PositionMismatch();
        ExactToken.checkReceipt(IC1Token(bindings.token0), address(this), idle0, uint128(net.amount0()));
        ExactToken.checkReceipt(IC1Token(bindings.token1), address(this), idle1, uint128(net.amount1()));
        BalanceDelta principal = net - fees;
        publishPosition();
        emit LiquidityExited(
            positionPoolId,
            positionSalt,
            liquidity,
            principal.amount0(),
            principal.amount1(),
            fees.amount0(),
            fees.amount1()
        );
    }

    /// @notice Install the final confirmed identity and liquidity in the bound service hook.
    function publishPosition() private {
        ServiceHook(bindings.hook).installPosition(positionLower, positionUpper, positionSalt, positionLiquidity);
    }

    /// @notice Read core liquidity under this vault's pool, owner, ticks and current salt.
    function actualLiquidity() private view returns (uint128 liquidity) {
        (liquidity,,) = IPoolManager(bindings.poolManager)
            .getPositionInfo(positionPoolId, address(this), positionLower, positionUpper, positionSalt);
    }

    /// @notice Bind an unlock to the requested leg and verify that the callback consumed its single-use context.
    function modifyPosition(Operation kind, int256 delta, uint256 limit0, uint256 limit1)
        private
        returns (BalanceDelta net, BalanceDelta fees)
    {
        IPoolManager.ModifyLiquidityParams memory params =
            IPoolManager.ModifyLiquidityParams(positionLower, positionUpper, delta, positionSalt);
        bytes memory data = abi.encode(kind, params, limit0, limit1);
        pendingUnlock = keccak256(data);
        bytes memory result = IPoolManager(bindings.poolManager).unlock(data);
        if (pendingUnlock != 0) revert InvalidOperation();
        (net, fees) = abi.decode(result, (BalanceDelta, BalanceDelta));
        uint128 actual = actualLiquidity();
        if (int256(uint256(actual)) != int256(uint256(positionLiquidity)) + delta) revert PositionMismatch();
        positionLiquidity = actual;
        if (kind != Operation.Seed && kind != Operation.Exit) {
            emit PositionAdjusted(kind, positionSalt, positionLower, positionUpper, actual, net - fees, fees);
        }
    }

    /// @dev Consume the unlock before interacting. Only the positive leg of this operation can admit an add.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != bindings.poolManager || pendingUnlock == 0 || keccak256(data) != pendingUnlock) {
            revert InvalidOperation();
        }
        delete pendingUnlock;
        IPoolManager core = IPoolManager(msg.sender);
        (Operation kind, IPoolManager.ModifyLiquidityParams memory params, uint256 limit0, uint256 limit1) =
            abi.decode(data, (Operation, IPoolManager.ModifyLiquidityParams, uint256, uint256));
        PoolKey memory key = poolKey();
        bool adding = params.liquidityDelta > 0;
        ServiceHook hook = ServiceHook(address(key.hooks));
        if (adding) hook.armAdd(kind, params);
        (BalanceDelta net, BalanceDelta fees) = core.modifyLiquidity(key, params, abi.encode(kind));
        if (adding && hook.pendingAdd() != 0) revert InvalidOperation();
        BalanceDelta principal = net - fees;
        checkPrincipal(principal.amount0(), adding, limit0);
        checkPrincipal(principal.amount1(), adding, limit1);
        settleCurrency(core, key.currency0, net.amount0());
        settleCurrency(core, key.currency1, net.amount1());
        return abi.encode(net, fees);
    }

    /// @notice Reject a signed principal delta outside the leg's input ceiling or output floor.
    function checkPrincipal(int128 amount, bool adding, uint256 limit) private pure {
        if (adding) {
            if (amount > 0 || uint256(-int256(amount)) > limit) revert PrincipalLimit();
        } else if (amount < 0 || uint128(amount) < limit) {
            revert PrincipalLimit();
        }
    }

    /// @notice Pay negative core deltas with exact tokens or take positive deltas into vault custody.
    function settleCurrency(IPoolManager core, Currency currency, int128 delta) private {
        IC1Token token = IC1Token(Currency.unwrap(currency));
        if (delta < 0) {
            uint256 due = uint256(-int256(delta));
            availableBalance(address(this), address(token), due);
            core.sync(currency);
            ExactToken.pay(token, address(core), due);
            if (core.settle() != due) revert SettlementMismatch();
        } else if (delta > 0) {
            uint256 due = uint128(delta);
            uint256 beforeCore = token.balanceOf(address(core));
            uint256 beforeVault = token.balanceOf(address(this));
            core.take(currency, address(this), due);
            ExactToken.checkDebit(token, address(core), beforeCore, due);
            ExactToken.checkReceipt(token, address(this), beforeVault, due);
        }
    }

    /// @notice Return actual base-unit custody and revert if the required amount is missing.
    function availableBalance(address custodian, address token, uint256 required)
        private
        view
        returns (uint256 balance)
    {
        balance = IC1Token(token).balanceOf(custodian);
        if (balance < required) revert InsufficientCustody(custodian, token, balance, required);
    }

    /// @notice Commit to the schema and complete typed terms, including the chain, vault and revision.
    function termsHash() public view returns (bytes32) {
        return keccak256(abi.encode(TERMS_SCHEMA, currentTerms()));
    }

    /// @notice Assemble the accepted domain, fixed beneficiaries, bindings and C1 quantities for independent encoding.
    function currentTerms() public view returns (Terms memory) {
        return Terms({
            chainId: creationChainId,
            vault: address(this),
            agreementId: agreementId,
            revision: revision,
            createdAt: createdAt,
            activationCutoff: activationCutoff,
            treasury: treasury,
            manager: manager,
            treasuryRecipient: treasury,
            managerRecipient: manager,
            bindings: bindings,
            paymentToken: bindings.token1,
            referenceBase: bindings.token0,
            referenceQuote: bindings.token1,
            parameters: c1Parameters(),
            rulesVersion: RULES_VERSION
        });
    }

    /// @notice Validate the new identities, increment revision and invalidate prior consent before publishing.
    function publishTerms(Bindings memory next) private {
        // C1 has separate parties, currencies, PoolManager, vault, hook and escrow.
        address[8] memory identities =
            [treasury, manager, next.token0, next.token1, next.poolManager, address(this), next.hook, next.escrow];
        for (uint256 i; i < identities.length; ++i) {
            if (identities[i] == address(0)) revert MissingAddress();
            for (uint256 j; j < i; ++j) {
                if (identities[i] == identities[j]) revert ConflictingIdentity(identities[i]);
            }
        }
        if (next.token0 > next.token1) revert UnsortedCurrencies();
        if (next.referenceAdapter == address(0) || next.referenceSource == address(0)) revert MissingAddress();

        bindings = next;
        ++revision;
        delete treasuryAcceptedRevision;
        delete managerAcceptedRevision;
        emit TermsPublished(revision, termsHash());
    }

    /// @notice Return the fixed C1 units, price and execution bounds shared by consent and execution.
    function c1Parameters() private pure returns (Parameters memory) {
        return Parameters({
            fee: 3000,
            tickSpacing: ServiceRange.SPACING,
            token0Decimals: 6,
            token1Decimals: 6,
            inventory0: 2_000_000_000,
            inventory1: 2_000_000_000,
            budget: 100_000_000,
            duration: 300,
            referenceDecimals: 8,
            maxReferenceAge: 60,
            bandHalfWidthBps: 100,
            seedLiquidity: 100_000_000_000,
            minLiquidity: ServiceRange.MIN_LIQUIDITY,
            maxLiquidity: 200_000_000_000,
            maxWidthTicks: ServiceRange.WIDTH,
            maxEdgeExtensionTicks: ServiceRange.EXTENSION,
            maxGrossInput0: 2_000_000_000,
            maxGrossInput1: 2_000_000_000,
            adjustmentCooldown: 30,
            maxExecutionWindow: 30
        });
    }
}
