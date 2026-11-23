// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Draft and acceptance component of the local C1 agreement.
contract AgreementVault {
    enum State {
        Draft,
        Accepted
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

    function revise(Bindings calldata next) external {
        if (msg.sender != treasury) revert NotTreasury();
        if (block.timestamp >= activationCutoff) revert CutoffReached();
        _publish(next);
    }

    function accept(bytes32 expectedHash) external {
        if (msg.sender != treasury && msg.sender != manager) revert NotParty();
        if (block.timestamp >= activationCutoff) revert CutoffReached();
        bytes32 current = termsHash();
        if (expectedHash != current) revert WrongTermsHash(expectedHash, current);

        if (msg.sender == treasury) {
            if (treasuryAcceptedRevision == revision) return;
            treasuryAcceptedRevision = revision;
        } else {
            if (managerAcceptedRevision == revision) return;
            managerAcceptedRevision = revision;
        }
        emit PartyAccepted(revision, current, msg.sender);
    }

    function state() external view returns (State) {
        if (treasuryAcceptedRevision == revision && managerAcceptedRevision == revision) return State.Accepted;
        return State.Draft;
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
