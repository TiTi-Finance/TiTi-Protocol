// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title The base vault module of TiTi Protocol
/// @author TiTi Protocol
/// @notice The module is used to manage funds in the protocol.
/// @dev Only the owner can call the params' update function, the owner will be transferred to Timelock in the future.
contract BaseVault is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Vault's name.
    string public vaultName;

    /// @notice Managed fund's token address .
    IERC20 public immutable baseToken;

    /// @notice Emitted when governor withdraws base token.
    event Withdraw(address indexed to, uint256 amount);

    constructor(string memory _vaultName, IERC20 _baseToken) {
        vaultName = _vaultName;
        baseToken = _baseToken;
    }

    /// @notice Governor withdraws base token.
    /// @param to Received address.
    /// @param amount Received amount.
    function withdraw(address to, uint256 amount) external virtual onlyOwner {
        baseToken.safeTransfer(to, amount);
        emit Withdraw(to, amount);
    }
}
