// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title The TimelockController module of TiTi Protocol
/// @author TiTi Protocol
/// @notice The module is used to manage the timelock logic in the protocol
contract TiTiTimelockController is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors) {
    }
}
