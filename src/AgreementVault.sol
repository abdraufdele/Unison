// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompensationEscrow} from "./CompensationEscrow.sol";
import {CustodyLock, ExactToken, IC1Token} from "./ExactToken.sol";

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

        CompensationEscrow escrow = CompensationEscrow(bindings.escrow);
        if (
            address(escrow).codehash != keccak256(type(CompensationEscrow).runtimeCode)
                || escrow.vault() != address(this) || address(escrow.paymentToken()) != bindings.token1
                || escrow.treasuryRecipient() != treasury || escrow.managerRecipient() != manager
                || escrow.fundedBudget() != 0 || escrow.refunded() != 0
        ) revert InvalidEscrow();

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
