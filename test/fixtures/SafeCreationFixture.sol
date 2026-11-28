// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {SafeProxyFactory} from "../../lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy, IProxy} from "../../lib/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {CreateCall} from "../../lib/safe-smart-account/contracts/libraries/CreateCall.sol";
import {Enum} from "../../lib/safe-smart-account/contracts/common/Enum.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {AgreementVault} from "../../src/AgreementVault.sol";
import {CustodyToken} from "./CustodyFixture.sol";
import {MockOpeningReferenceAdapter} from "./MockOpeningReferenceAdapter.sol";

/// @dev Wire ABI used with the original SafeL2 release bytecode. Solidity 0.8.26 only compiles the caller.
interface ISafeL2 {
    /// @notice Initialize the proxy with its owner set, threshold and optional setup/payment fields.
    function setup(
        address[] calldata members,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
    /// @notice Return the current Safe transaction nonce.
    function nonce() external view returns (uint256);
    /// @notice Return the distinct authorized owners.
    function getOwners() external view returns (address[] memory);
    /// @notice Return the minimum number of confirmations.
    function getThreshold() external view returns (uint256);
    /// @notice Test whether an address belongs to the owner list.
    function isOwner(address member) external view returns (bool);
    /// @notice Hash the transaction fields and explicit review nonce in the Safe's signing domain.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 safeNonce
    ) external view returns (bytes32);
    /// @notice Verify the packed signatures against the current nonce and execute the inner operation.
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures
    ) external payable returns (bool);
}

abstract contract SafeCreationFixture {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant ID = keccak256("Unison local Safe ownership fixture");
    string internal constant VAULT_ARTIFACT = "AgreementVault.sol:AgreementVault";
    bytes32 internal constant CREATION = keccak256("ContractCreation(address)");
    bytes32 internal constant SUCCESS = keccak256("ExecutionSuccess(bytes32,uint256)");
    bytes32 internal constant PUBLISHED = keccak256("TermsPublished(uint256,bytes32)");

    ISafeL2 internal safe;
    CreateCall internal helper;
    address internal manager;
    address internal executor;
    Vm.Wallet[3] internal owners;
    AgreementVault.Bindings internal draft;

    struct Request {
        address target;
        bytes data;
        Enum.Operation operation;
        uint256 nonce;
    }

    /// @notice Execute original release constructor bytes and require the canonical deployed code hash.
    function deployRelease(string memory name, bytes32 runtimeHash) private returns (address instance) {
        string memory json = vm.readFile(string.concat(".local/safe-release/", name, ".json"));
        bytes memory init = vm.parseJsonBytes(json, ".bytecode");
        assembly ("memory-safe") {
            instance := create(0, add(init, 32), mload(init))
        }
        require(instance != address(0) && instance.codehash == runtimeHash, "Safe release runtime");
    }

    /// @notice Initialize a real proxy in its factory transaction and build the unfunded local draft bindings.
    function setUp() public {
        vm.chainId(31337);
        address[] memory members = new address[](3);
        for (uint256 i; i < members.length; ++i) {
            owners[i] = vm.createWallet(string.concat("local Safe owner ", vm.toString(i)));
            members[i] = owners[i].addr;
        }
        manager = vm.createWallet("local C1 manager").addr;
        executor = vm.createWallet("local Safe executor").addr;
        address singleton = deployRelease("SafeL2", 0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff);
        SafeProxyFactory factory = SafeProxyFactory(
            deployRelease("SafeProxyFactory", 0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317)
        );
        helper =
            CreateCall(deployRelease("CreateCall", 0x2b3060c55fcb8275653e99ad511a71f67ba76934ed66a7d74d6e68b52afff889));
        bytes memory setup = abi.encodeCall(
            ISafeL2.setup, (members, 2, address(0), bytes(""), address(0), address(0), 0, payable(address(0)))
        );
        vm.prank(executor);
        SafeProxy proxy = factory.createProxyWithNonce(singleton, setup, 1);
        safe = ISafeL2(address(proxy));
        require(
            address(proxy).codehash == 0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c,
            "proxy runtime"
        );
        require(IProxy(address(proxy)).masterCopy() == singleton, "singleton");
        require(keccak256(abi.encode(safe.getOwners())) == keccak256(abi.encode(members)), "owners");
        require(safe.getThreshold() == 2 && safe.nonce() == 0, "initial threshold/nonce");
        require(!safe.isOwner(manager) && !safe.isOwner(executor) && executor != manager, "actor overlap");
        address core = vm.deployCode("PoolManager.sol:PoolManager", abi.encode(address(safe)));
        address a = address(new CustodyToken());
        address b = address(new CustodyToken());
        address adapter = address(new MockOpeningReferenceAdapter());
        draft = AgreementVault.Bindings({
            poolManager: core,
            token0: a < b ? a : b,
            token1: a < b ? b : a,
            hook: address(uint160(uint256(keccak256(abi.encode(ID, "draft hook"))))),
            escrow: address(uint160(uint256(keccak256(abi.encode(ID, "draft escrow"))))),
            referenceAdapter: adapter,
            referenceSource: adapter
        });
        require(draft.hook.code.length == 0 && draft.escrow.code.length == 0, "occupied draft placeholder");
    }

    /// @notice Bind the complete current vault creation bytes to the helper call at the reviewed Safe nonce.
    function creationRequest(Enum.Operation operation) internal view returns (Request memory) {
        bytes memory init = bytes.concat(vm.getCode(VAULT_ARTIFACT), abi.encode(ID, manager, draft));
        return Request(address(helper), abi.encodeCall(CreateCall.performCreate, (0, init)), operation, safe.nonce());
    }

    /// @notice Obtain the chain/proxy-domain digest using zero value, Safe gas and reimbursement fields.
    function digest(Request memory request) internal view returns (bytes32) {
        return safe.getTransactionHash(
            request.target, 0, request.data, request.operation, 0, 0, 0, address(0), address(0), request.nonce
        );
    }

    /// @notice Sign a typed digest with a disposable Foundry wallet and return Safe's packed ECDSA format.
    function signature(Vm.Wallet memory wallet, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallet.privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Sort the two signatures by owner address, independently of caller or wallet creation order.
    function signedPair(bytes32 hash, Vm.Wallet memory first, Vm.Wallet memory second)
        internal
        pure
        returns (bytes memory)
    {
        if (first.addr > second.addr) (first, second) = (second, first);
        return bytes.concat(signature(first, hash), signature(second, hash));
    }

    /// @notice Submit only as the non-owner executor. The Safe verifies signatures against its live nonce.
    function execute(Request memory request, bytes memory signatures) internal returns (bool) {
        vm.prank(executor);
        return safe.execTransaction(
            request.target, 0, request.data, request.operation, 0, 0, 0, address(0), payable(address(0)), signatures
        );
    }

    /// @notice Require exactly one matching event from the specified contract.
    function eventFrom(Vm.Log[] memory logs, address emitter, bytes32 topic)
        internal
        pure
        returns (Vm.Log memory result)
    {
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                result = logs[i];
                ++count;
            }
        }
        require(count == 1, "missing or repeated event");
    }

    /// @notice Match both execution success and the signed hash, including zero executor reimbursement.
    function assertSuccess(Vm.Log[] memory logs, bytes32 hash) internal view {
        Vm.Log memory result = eventFrom(logs, address(safe), SUCCESS);
        require(result.topics.length == 2 && result.topics[1] == hash, "wrong Safe execution hash");
        require(abi.decode(result.data, (uint256)) == 0, "unexpected reimbursement");
    }

    /// @notice Resolve the vault from the creation event, then corroborate the creator with its EVM account nonce.
    function createWithPair(uint256 first, uint256 second, Enum.Operation operation)
        internal
        returns (AgreementVault vault)
    {
        Request memory request = creationRequest(operation);
        bytes32 hash = digest(request);
        bytes memory signatures = signedPair(hash, owners[first], owners[second]);
        address creator = operation == Enum.Operation.DelegateCall ? address(safe) : address(helper);
        uint64 createNonce = vm.getNonce(creator);
        vm.recordLogs();
        require(execute(request, signatures), "inner creation failed");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertSuccess(logs, hash);
        Vm.Log memory created = eventFrom(logs, creator, CREATION);
        require(created.topics.length == 2, "creation event");
        vault = AgreementVault(address(uint160(uint256(created.topics[1]))));
        require(address(vault) == vm.computeCreateAddress(creator, createNonce), "CREATE address");
        require(vm.getNonce(creator) == createNonce + 1 && safe.nonce() == request.nonce + 1, "creation nonces");
        assertPublication(logs, vault, 1);
    }

    /// @notice Compare the recorded publication with a fresh hash encoding on the actual vault.
    function assertPublication(Vm.Log[] memory logs, AgreementVault vault, uint256 revision) internal view {
        bytes32 expected = keccak256(abi.encode(vault.TERMS_SCHEMA(), vault.currentTerms()));
        Vm.Log memory publication = eventFrom(logs, address(vault), PUBLISHED);
        require(publication.topics.length == 3 && publication.topics[1] == bytes32(revision), "published revision");
        require(publication.topics[2] == expected && vault.termsHash() == expected, "published terms");
    }
}
