// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompensationEscrow} from "./CompensationEscrow.sol";
import {CustodyLock, ExactToken, IC1Token} from "./ExactToken.sol";

import {IOpeningReferenceAdapter} from "./IOpeningReferenceAdapter.sol";
import {OpeningBand} from "./OpeningBand.sol";
import {SeedPool} from "./SeedPool.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/// @notice C1 consent, funding and pre-activation cancellation.
contract AgreementVault is CustodyLock {
    enum State {
        Draft,
        Accepted,
        Funded,
        Cancelled
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

    constructor(bytes32 id, address namedManager, Bindings memory initialBindings) {
        if (id == bytes32(0)) revert MissingAgreementId();
        creationChainId = block.chainid;
        agreementId = id;
        createdAt = block.timestamp;
        activationCutoff = block.timestamp + 1 days;
        treasury = msg.sender;
        manager = namedManager;
        _publish(initialBindings);
    }

    function revise(Bindings calldata next) external nonReentrant {
        if (msg.sender != treasury) revert NotTreasury();
        _requireOpenTerms();
        _publish(next);
    }

    function accept(bytes32 expectedHash) external nonReentrant {
        if (msg.sender != treasury && msg.sender != manager) revert NotParty();
        _requireOpenTerms();
        _checkHash(expectedHash);

        if (msg.sender == treasury) {
            if (treasuryAcceptedRevision == revision) return;
            treasuryAcceptedRevision = revision;
        } else {
            if (managerAcceptedRevision == revision) return;
            managerAcceptedRevision = revision;
        }
        emit PartyAccepted(revision, expectedHash, msg.sender);
    }

    function _requireOpenTerms() private view {
        if (cancelled || fundedPrincipal0 != 0) revert TermsClosed();
        if (block.timestamp >= activationCutoff) revert CutoffReached();
    }

    function _checkHash(bytes32 expectedHash) private view {
        bytes32 current = termsHash();
        if (expectedHash != current) revert WrongTermsHash(expectedHash, current);
    }

    function state() public view returns (State) {
        if (cancelled) return State.Cancelled;
        if (fundedPrincipal0 != 0) return State.Funded;
        if (treasuryAcceptedRevision == revision && managerAcceptedRevision == revision) return State.Accepted;
        return State.Draft;
    }

    function fund(bytes32 expectedHash) external nonReentrant {
        if (msg.sender != treasury) revert NotTreasury();
        _requireOpenTerms();
        _checkHash(expectedHash);
        if (state() != State.Accepted) revert NotAccepted();

        CompensationEscrow escrow = _checkedEscrow(0);
        Parameters memory p = _c1Parameters();
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

    function _checkedEscrow(uint256 expectedBudget) private view returns (CompensationEscrow escrow) {
        escrow = CompensationEscrow(bindings.escrow);
        if (
            address(escrow).codehash != keccak256(type(CompensationEscrow).runtimeCode)
                || escrow.vault() != address(this) || address(escrow.paymentToken()) != bindings.token1
                || escrow.treasuryRecipient() != treasury || escrow.managerRecipient() != manager
                || escrow.fundedBudget() != expectedBudget || escrow.refunded() != 0
        ) revert InvalidEscrow();
    }

    function cancel() external nonReentrant {
        if (msg.sender != treasury && block.timestamp < activationCutoff) revert NotTreasury();
        if (cancelled) return;
        cancelled = true;
        emit Cancelled(revision, termsHash(), msg.sender);
    }

    function withdrawIdle() external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (msg.sender != treasury) revert NotTreasury();
        if (!cancelled) revert NotCancelled();
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
        Parameters memory p = _c1Parameters();
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
        (lower, upper) =
            OpeningBand.calculate(uint256(observed.answer), p.tickSpacing, p.bandHalfWidthBps, p.maxWidthTicks);
    }

    /// @notice Inspect feasibility at this instant. Activation must execute this check again before seeding.
    function preflightActivation(bytes32 expectedHash) public view returns (ActivationPreflight memory result) {
        if (state() != State.Funded) revert NotFunded();
        _checkHash(expectedHash);
        if (block.chainid != creationChainId) revert WrongChain();
        if (treasuryAcceptedRevision != revision || managerAcceptedRevision != revision) revert NotAccepted();
        if (block.timestamp >= activationCutoff) revert CutoffReached();

        Parameters memory p = _c1Parameters();
        if (fundedPrincipal0 != p.inventory0 || fundedPrincipal1 != p.inventory1) revert IncompleteFunding();
        CompensationEscrow escrow = _checkedEscrow(p.budget);
        result.escrowBalance = _available(address(escrow), bindings.token1, p.budget);

        (result.observation, result.lower, result.upper) = previewOpeningReference();
        if (p.seedLiquidity == 0 || p.seedLiquidity < p.minLiquidity || p.seedLiquidity > p.maxLiquidity) {
            revert InvalidSeedLiquidity();
        }
        PoolKey memory key = PoolKey(
            Currency.wrap(bindings.token0), Currency.wrap(bindings.token1), p.fee, p.tickSpacing, IHooks(bindings.hook)
        );
        result.seed =
            SeedPool.inspect(IPoolManager(bindings.poolManager), key, result.lower, result.upper, p.seedLiquidity);
        if (result.seed.amount0 > p.maxGrossInput0 || result.seed.amount1 > p.maxGrossInput1) revert SeedInputLimit();
        // Each actual vault balance must cover both the original mandate and its quoted seed leg.
        result.available0 = _available(
            address(this), bindings.token0, p.inventory0 > result.seed.amount0 ? p.inventory0 : result.seed.amount0
        );
        result.available1 = _available(
            address(this), bindings.token1, p.inventory1 > result.seed.amount1 ? p.inventory1 : result.seed.amount1
        );
    }

    function _available(address custodian, address token, uint256 required) private view returns (uint256 balance) {
        balance = IC1Token(token).balanceOf(custodian);
        if (balance < required) revert InsufficientCustody(custodian, token, balance, required);
    }

    function termsHash() public view returns (bytes32) {
        return keccak256(abi.encode(TERMS_SCHEMA, currentTerms()));
    }

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
            parameters: _c1Parameters(),
            rulesVersion: RULES_VERSION
        });
    }

    function _publish(Bindings memory next) private {
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

    function _c1Parameters() private pure returns (Parameters memory) {
        return Parameters({
            fee: 3000,
            tickSpacing: 60,
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
            minLiquidity: 100_000_000_000,
            maxLiquidity: 200_000_000_000,
            maxWidthTicks: 480,
            maxEdgeExtensionTicks: 120,
            maxGrossInput0: 2_000_000_000,
            maxGrossInput1: 2_000_000_000,
            adjustmentCooldown: 30,
            maxExecutionWindow: 30
        });
    }
}
