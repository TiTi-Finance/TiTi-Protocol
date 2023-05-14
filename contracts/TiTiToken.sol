// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title The core control module of TiTi Protocol
/// @author TiTi Protocol
/// @notice The module is used to update the key parameters in the protocol.
/// @dev Only the owner can call the params' update function, the owner will be transferred to Timelock in the future.
contract TiTiToken is ERC20Burnable, ERC20Snapshot, ERC20Votes, AccessControl {
    /// @notice TiTi's max supply is 1 billion.
    uint256 public constant MAX_TOTAL_SUPPLY = 1000000000 * 1e18;

    /// @notice Snapshot role's flag.
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

    /// @notice Minter role's flag.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Emitted when new admin is set.
    event NewAdmin(address indexed oldAdmin, address indexed newAdmin);

    constructor() ERC20("TiTi", "TiTi") ERC20Permit("TiTi") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SNAPSHOT_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(SNAPSHOT_ROLE, DEFAULT_ADMIN_ROLE);

        _mint(msg.sender, MAX_TOTAL_SUPPLY);
    }

    /// @notice Set new admin and the old one's role will be revoked.
    /// @param _newAdmin New admin address.
    function setNewAdmin(address _newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newAdmin != address(0), "TiTiToken: Zero Address");
        address _oldAdmin = msg.sender;
        _setupRole(DEFAULT_ADMIN_ROLE, _newAdmin);
        revokeRole(DEFAULT_ADMIN_ROLE, _oldAdmin);
        emit NewAdmin(_oldAdmin, _newAdmin);
    }

    /// @notice Batch set new minters.
    /// @param _newMinters New minters' address.
    function setNewMinters(address[] memory _newMinters) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint i; i < _newMinters.length; i++) {
            require(_newMinters[i] != address(0), "TiTiToken: Zero Address");
            _setupRole(MINTER_ROLE, _newMinters[i]);
        }
    }

    /// @notice Creates a new snapshot and returns its snapshot id.
    /// @return snapshot_id New snapshot id. 
    function snapshot() external onlyRole(SNAPSHOT_ROLE) returns (uint256) {
        return _snapshot();
    }

    /// @notice Mint more TiTi token.
    /// @param to Received address.
    /// @param amount Received amount.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Snapshot)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        uint256 lastTotalSupply = totalSupply();
        require(lastTotalSupply + amount <= MAX_TOTAL_SUPPLY, "TiTiToken: Exceeds the maximum supply");
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}