// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import '../interfaces/ITiTiStaking.sol';

/// @title The Use-To-Earn's reward distributor of TiTi Protocol
/// @author TiTi Protocol
/// @notice This module is used to distribute the rewards in Use-To-Earn's activity.
/// @dev Only the owner can call the params' update function, the owner will be transferred to Timelock in the future.
contract TiTiMerkleDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Merkle root for latest reward distribution.
    bytes32 public root;

    /// @notice TiTi contract address.
    IERC20 public immutable token;

    /// @notice TiTiStakingPool contract address.
    ITiTiStaking public staking;

    /// @notice TiTiStakingPool updating merkle root worker address.
    address private merkleRootWorker;

    /// @notice TiTiStakingPool deposit worker address.
    address private depositWorker;

    /// @notice Users' claimed record.
    mapping(address => uint) public claimed;

    /// @notice Emitted when new TiTi reward merkle root is set.
    event UpdateRoot(bytes32 indexed root);

    /// @notice Emitted when new TiTiStakingPool is set.
    event UpdateStaking(address staking);

    /// @notice Emitted when governor deposits new TiTi rewards.
    event Deposit(uint amount);

    /// @notice Emitted when a user claims TiTi rewards.
    event Claim(address indexed account, uint claimAmount);

    /// @notice Emitted when a user claims TiTi rewards and auto stakes these into the TiTIStakingPool.
    event ClaimAndStake(address indexed account, uint claimAmount);

    /// @notice Emitted when governor withdraws tokens in unexpected scenarios. Emergency use only!.
    event Extract(address indexed token, uint amount);

    /// @notice Emitted when new updating merkle root worker is set.
    event NewMerkleRootWorker(address account);

    /// @notice Emitted when new deposit worker is set.
    event NewDepositWorker(address account);

    modifier onlyMerkleRootWorker() {
        require(msg.sender == merkleRootWorker || msg.sender == owner(), 'TiTiMerkleDistributor: Not MerkleRoot Worker');
        _;
    }

    modifier onlyDepositWorker() {
        require(msg.sender == depositWorker || msg.sender == owner(), 'TiTiMerkleDistributor: Not Deposit Worker');
        _;
    }

    constructor(address _token, address _staking, bytes32 _root) {
        token = IERC20(_token);
        _updateMerkleRoot(_root);
        _updateStaking(_staking);
    }

    /// @notice Set new updating merkle root worker and emit NewMerkleRootWorker event.
    /// @param _merkleRootWorker New update merkle root worker address.
    function setMerkleRootWorker(address _merkleRootWorker) external onlyOwner {
        require(_merkleRootWorker != address(0), "TiTiMerkleDistributor: Zero Address");
        merkleRootWorker = _merkleRootWorker;
        emit NewMerkleRootWorker(_merkleRootWorker);
    }

    /// @notice Set new deposit worker and emit NewDepositWorker event.
    /// @param _depositWorker New deposit address.
    function setDepositWorker(address _depositWorker) external onlyOwner {
        require(_depositWorker != address(0), "TiTiMerkleDistributor: Zero Address");
        depositWorker = _depositWorker;
        emit NewDepositWorker(_depositWorker);
    }

    /// @notice Update TiTiStakingPool contract address.
    /// @param _staking New TiTiStakingPool contract address.
    function updateStaking(address _staking) external onlyOwner {
        _updateStaking(_staking);
    }

    /// @notice Update the latest reward distribution's merkle root.
    /// @param _root New merkle root.
    function updateMerkleRoot(bytes32 _root) external onlyMerkleRootWorker {
        _updateMerkleRoot(_root);
    }
    
    /// @notice Governor deposits new TiTi rewards.
    /// @param _amount New TiTi rewards' amount.
    function deposit(uint _amount) external onlyDepositWorker {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(_amount);
    }

    /// @notice Users claim TiTi rewards and auto-stake these into the TiTIStakingPool..
    /// @param _reward Target user's TiTi rewards' amount.
    /// @param _proof Target user's claimed proof.
    function claimAndStake(uint _reward, bytes32[] calldata _proof) external nonReentrant {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _reward));
        require(MerkleProof.verify(_proof, root, leaf), 'TiTiMerkleDistributor: Invalid Proof');
        uint claimAmount = _reward - claimed[msg.sender];
        require(claimAmount > 0, "TiTiMerkleDistributor: Account don't have reward to claim");

        claimed[msg.sender] = _reward;
        token.safeTransfer(msg.sender, claimAmount);
        staking.stake(msg.sender, claimAmount);
        emit ClaimAndStake(msg.sender, claimAmount);
    }

    /// @notice Users claim TiTi rewards.
    /// @param _reward Target user's TiTi rewards' amount.
    /// @param _proof Target user's claimed proof.
    function claim(uint _reward, bytes32[] calldata _proof) external nonReentrant {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _reward));
        require(MerkleProof.verify(_proof, root, leaf), 'TiTiMerkleDistributor: Invalid Proof');
        uint claimAmount = _reward - claimed[msg.sender];
        require(claimAmount > 0, "TiTiMerkleDistributor: Account don't have reward to claim");

        claimed[msg.sender] = _reward;
        token.safeTransfer(msg.sender, claimAmount);
        emit Claim(msg.sender, claimAmount);
    }

    /// @notice Governor withdraws tokens in unexpected scenarios. Emergency use only!
    /// @param _token Target token address.
    /// @param _amount Withdrawal amount.
    function extract(address _token, uint _amount) external onlyOwner {
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit Extract(_token, _amount);
    }

    function _updateMerkleRoot(bytes32 _root) internal {
        root = _root;
        emit UpdateRoot(_root);
    }

    function _updateStaking(address _staking) internal {
        require(_staking != address(0), "TiTiMerkleDistributor: Zero Address");
        staking = ITiTiStaking(_staking);
        emit UpdateStaking(_staking);
    }
}
