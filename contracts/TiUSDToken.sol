// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title The core control module of TiTi Protocol
/// @author TiTi Protocol
/// @notice The module is used to update the key parameters in the protocol.
/// @dev Only the owner can call the params' update function, the owner will be transferred to Timelock in the future.
contract TiUSDToken is ERC20Burnable, ERC20Snapshot, ERC20Permit, AccessControl {
    /// @notice Snapshot role's flag.
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

    /// @notice Minter role's flag.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Emitted when reorders is triggered.
    event ReOrders(address mamm, bool isPositive, uint256 amount);

    /// @notice Emitted when new admin is set.
    event NewAdmin(address indexed oldAdmin, address indexed newAdmin);

    constructor() ERC20("TiUSD", "TiUSD") ERC20Permit("TiUSD") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SNAPSHOT_ROLE, msg.sender);
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(SNAPSHOT_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /// @notice Set new admin and the old one's role will be revoked.
    /// @param _newAdmin New admin address.
    function setNewAdmin(address _newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address _oldAdmin = msg.sender;
        _setupRole(DEFAULT_ADMIN_ROLE, _newAdmin);
        revokeRole(DEFAULT_ADMIN_ROLE, _oldAdmin);
        emit NewAdmin(_oldAdmin, _newAdmin);
    }

    /// @notice Creates a new snapshot and returns its snapshot id.
    /// @return snapshot_id New snapshot id. 
    function snapshot() external onlyRole(SNAPSHOT_ROLE) returns (uint256) {
        return _snapshot();
    }

    /// @notice Mint more TiUSD token.
    /// @param to Received address.
    /// @param amount Received amount.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice ReOrdersController can call this function to complete the mamm's TiUSD balance adjustment during the reorders process.
    /// @param mamm MAMMSwapPair contract address.
    /// @param isPositive Whether it needs to mint or burn TiUSD.
    /// @param amount TiUSD amount to be adjusted.
    function reorders(address mamm, bool isPositive, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (isPositive) {
            _mint(mamm, amount);
        } else {
            _burn(mamm, amount);
        }
        emit ReOrders(mamm, isPositive, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Snapshot)
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}