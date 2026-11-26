// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AgreementVault} from "../../src/AgreementVault.sol";
import {CompensationEscrow} from "../../src/CompensationEscrow.sol";
import {IC1Token, CustodyLock} from "../../src/ExactToken.sol";
import {Vm} from "../AgreementVaultAcceptance.t.sol";

interface ITransferProbe {
    /// @notice Run the test's configured probe during a mock token transfer.
    function onTransfer() external;
}

/// @dev Local adversarial ERC-20 fixture. Faults apply to just one sender/recipient route.
contract CustodyToken is IC1Token {
    enum Fault {
        None,
        Revert,
        FalseReturn,
        ShortReceipt,
        ExtraDebit,
        NoReturn,
        InvalidReturn,
        ChangePriorBalance
    }
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address private faultSender;
    address private faultRecipient;
    Fault private fault;
    ITransferProbe private probe;

    /// @notice Increase the fixture balance of the specified recipient in base units.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    /// @notice Override the mock denomination for metadata validation tests.
    function setDecimals(uint8 value) external {
        decimals = value;
    }

    /// @notice Select a transfer result for one sender and recipient in the local token.
    function setFault(address sender, address recipient, Fault value) external {
        faultSender = sender;
        faultRecipient = recipient;
        fault = value;
    }

    /// @notice Configure the callback probe used during a mock transfer.
    function setProbe(ITransferProbe target) external {
        probe = target;
    }

    /// @notice Set the mock spender's allowance in token base units.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Spend the caller's allowance and apply any route-specific mock behavior.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        return moveMockTokens(from, to, amount);
    }

    /// @notice Apply the mock route behavior to a caller-funded transfer.
    function transfer(address to, uint256 amount) external returns (bool) {
        return moveMockTokens(msg.sender, to, amount);
    }

    /// @notice Apply the selected route fault and record the mock token's actual debit and credit.
    function moveMockTokens(address from, address to, uint256 amount) private returns (bool) {
        Fault active = from == faultSender && to == faultRecipient ? fault : Fault.None;
        require(active != Fault.Revert, "blocked route");
        balanceOf[from] -= amount;
        balanceOf[to] += active == Fault.ShortReceipt ? amount - 1 : amount;
        if (active == Fault.ExtraDebit) --balanceOf[from];
        // On the final budget leg, disturb the vault's earlier principal B receipt.
        if (active == Fault.ChangePriorBalance) --balanceOf[msg.sender];
        if (address(probe) != address(0)) probe.onTransfer();
        if (active == Fault.NoReturn) {
            assembly ("memory-safe") { return(0, 0) }
        }
        if (active == Fault.InvalidReturn) {
            assembly ("memory-safe") {
                mstore(0, 2)
                return(0, 32)
            }
        }
        return active != Fault.FalseReturn;
    }
}

abstract contract CustodyFixture is ITransferProbe {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant MANAGER = address(0x2222);
    address internal constant DONOR = address(0x3333);
    uint256 internal constant PRINCIPAL = 2_000_000_000;
    uint256 internal constant BUDGET = 100_000_000;

    AgreementVault internal vault;
    CompensationEscrow internal escrow;
    CustodyToken internal a;
    CustodyToken internal b;
    enum Probe {
        Funding,
        Withdrawal,
        Refund
    }
    Probe internal probe;
    uint256 internal blockedCalls;

    /// @notice Create the initial vault and actors shared by this suite before each test.
    function setUp() public {
        a = new CustodyToken();
        b = new CustodyToken();
        if (address(a) > address(b)) (a, b) = (b, a);
        AgreementVault.Bindings memory bindings = AgreementVault.Bindings({
            poolManager: address(0x3000),
            token0: address(a),
            token1: address(b),
            hook: address(0x6000),
            escrow: address(0x7000),
            referenceAdapter: address(0x8000),
            referenceSource: address(0x9000)
        });
        vault = new AgreementVault(bytes32(uint256(1)), MANAGER, bindings);
        escrow = new CompensationEscrow(address(vault), b, address(this), MANAGER);
        bindings.escrow = address(escrow);
        vault.revise(bindings);
        a.mint(address(this), PRINCIPAL);
        b.mint(address(this), PRINCIPAL + BUDGET);
        a.approve(address(vault), PRINCIPAL);
        b.approve(address(vault), PRINCIPAL + BUDGET);
    }

    /// @notice Record the selected fixture parties' decisions against the vault's current proposal.
    function acceptTerms() internal {
        bytes32 h = vault.termsHash();
        vault.accept(h);
        vm.prank(MANAGER);
        vault.accept(h);
    }

    /// @notice Obtain both consents and deposit principal and compensation from the fixture treasury.
    function fundFixture() internal {
        acceptTerms();
        vault.fund(vault.termsHash());
    }

    /// @notice Credit a recipient with extra mock units outside the agreement's funded rights.
    function giveTokens(CustodyToken token, address to, uint256 amount) internal {
        token.mint(DONOR, amount);
        vm.prank(DONOR);
        require(token.transfer(to, amount), "gift failed");
    }

    /// @notice Compare treasury, vault and escrow balances in token base units.
    function assertCustodyBalances(
        uint256 treasuryA,
        uint256 treasuryB,
        uint256 vaultA,
        uint256 vaultB,
        uint256 escrowB
    ) internal view {
        require(a.balanceOf(address(this)) == treasuryA && b.balanceOf(address(this)) == treasuryB, "treasury balances");
        require(a.balanceOf(address(vault)) == vaultA && b.balanceOf(address(vault)) == vaultB, "principal custody");
        require(b.balanceOf(address(escrow)) == escrowB, "budget custody");
    }

    /// @dev The treasury fixture calls the actual entry points; the lock must reject an otherwise authorized caller.
    function onTransfer() public virtual {
        require(msg.sender == address(a) || msg.sender == address(b), "fixture token only");
        if (probe == Probe.Funding) {
            try vault.fund(vault.termsHash()) {
                revert("nested funding");
            } catch (bytes memory err) {
                expectLockedCall(err);
            }
            try vault.cancel() {
                revert("nested cancellation");
            } catch (bytes memory err) {
                expectLockedCall(err);
            }
        } else if (probe == Probe.Withdrawal) {
            try vault.withdrawIdle() {
                revert("nested withdrawal");
            } catch (bytes memory err) {
                expectLockedCall(err);
            }
        } else {
            try escrow.refund() {
                revert("nested refund");
            } catch (bytes memory err) {
                expectLockedCall(err);
            }
        }
    }

    /// @notice Require the attempted callback to fail with the custody lock's expected error.
    function expectLockedCall(bytes memory err) private {
        require(bytes4(err) == CustodyLock.ReentrantCall.selector, "wrong callback rejection");
        ++blockedCalls;
    }
}
