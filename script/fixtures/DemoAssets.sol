// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOpeningReferenceAdapter} from "../../src/IOpeningReferenceAdapter.sol";

/// @notice Fixed-supply six-decimal asset for disposable C1 demonstrations.
contract DemoToken is ERC20 {
    /// @notice Issue the fixture inventory and trader inventory to the creating treasury.
    constructor() ERC20("Unison demo asset", "DEMO") {
        _mint(msg.sender, 10_000_000_000);
    }

    /// @notice Express C1 inventory and compensation in millionths of a demo token.
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract DemoReference is IOpeningReferenceAdapter {
    address public immutable publisher;
    Observation private current;

    /// @notice Bind a parity observation to the ordered demo assets and its only publisher.
    constructor(address base, address quote) {
        publisher = msg.sender;
        current = Observation(address(this), base, quote, 6, 6, 8, 1e8, block.timestamp, true);
    }

    /// @notice Refresh this fixture's parity timestamp on a supported demonstration network.
    function refresh() external {
        require(msg.sender == publisher && (block.chainid == 31337 || block.chainid == 1301), "fixture publisher");
        current.updatedAt = block.timestamp;
    }

    /// @notice Return the most recently published fixture observation.
    function observation() external view returns (Observation memory) {
        return current;
    }
}
