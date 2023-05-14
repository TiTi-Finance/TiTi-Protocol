// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./BaseVault.sol";

/// @title The Protocol Fee Vault module of TiTi Protocol
/// @author TiTi Protocol
/// @notice The module is used to manage the protocol fee in the protocol
contract ProtocolFeeVault is BaseVault {
    constructor(IERC20 _baseToken) BaseVault("ProtocolFeeVault", _baseToken) {
    }
}
