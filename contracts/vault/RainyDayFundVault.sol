// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./BaseVault.sol";

/// @title The Rainy Day Fund Vault module of TiTi Protocol
/// @author TiTi Protocol
/// @notice The module is used to manage the rainy day fund in the protocol
contract RainyDayFundVault is BaseVault {
    constructor(IERC20 _baseToken) BaseVault("RainyDayFundVault", _baseToken) {
    }
}

