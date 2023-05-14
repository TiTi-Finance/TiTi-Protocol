// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @dev Import from
 * https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/proxy/utils/Initializable.sol
 */
abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}


/**
 * @dev Import from
 * https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/security/ReentrancyGuardUpgradeable.sol
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    uint256[49] private __gap;
}


/// @title The TiTi Staking module of TiTi Protocol
/// @author TiTi Protocol
/// @notice This module is used to implement the functionality of the TiTi Staking module.
/// @dev Only the owner can call the params' update function, the owner will be transferred to Timelock in the future.
contract TiTiStakingV1 is ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Users' staked status data.
    struct Data {
        uint status;
        uint share;
        uint unbondTime;
        uint unbondShare;
    }
    
    /// @notice TiTi contract address.
    IERC20Upgradeable public titi;

    /// @notice Governor address.
    address public governor;

    /// @notice PendingGovernor address.
    address public pendingGovernor;

    /// @notice TiTi reward distributor contract address.
    address public worker;

    /// @notice TiTiMerkleDistributor contract address.
    address public merkle;

    /// @notice Current version.
    uint public constant VERSION = 1;

    /// @notice Staked status flag.
    uint public constant STATUS_READY = 0;

    /// @notice Unbonding status flag.
    uint public constant STATUS_UNBONDING = 1;

    /// @notice Unbonding lasts 30 days.
    uint public constant UNBONDING_DURATION = 30 days;

    /// @notice After Unbonding is over, there is a 3-day withdrawal duration.
    uint public constant WITHDRAW_DURATION = 3 days;

    /// @notice Total TiTi staked.
    uint public totalTiTi;

    /// @notice Total staked TiTi share.
    uint public totalShare;

    /// @notice All users' staked status data.
    mapping(address => Data) public users;

    /// @notice Emitted when new TiTi reward distributor is set.
    event NewWorker(address worker);

    /// @notice Emitted when new TiTiMerkleDistributor is set.
    event NewMerkle(address merkle);

    /// @notice Emitted when new pending governor is set.
    event NewPendingGovernor(address newAddr);

    /// @notice Emitted when new governor is set.
    event NewGovernor(address oldAddr, address newAddr);

    /// @notice Emitted when a user stakes new TiTi.
    event Stake(address owner, uint share, uint amount);

    /// @notice Emitted when a user unbonds TiTi .
    event Unbond(address owner, uint unbondTime, uint unbondShare);

    /// @notice Emitted when a user withdraws TiTi.
    event Withdraw(address owner, uint withdrawShare, uint withdrawAmount);

    /// @notice Emitted when a user cancels the unbonding request.
    event CancelUnbond(address owner, uint unbondTime, uint unbondShare);

    /// @notice Emitted when new TiTi rewards are distributed.
    event Reward(address worker, uint rewardAmount);

    /// @notice Emitted when skim happens.
    event Skim(address to, uint amount);

    modifier onlyGov() {
        require(msg.sender == governor, 'TiTiStakingV1: Not Governor');
        _;
    }

    modifier onlyWorker() {
        require(msg.sender == worker || msg.sender == governor, 'TiTiStakingV1: Not Worker');
        _;
    }

    /// @notice Initialize the entire contract.
    /// @param _titi TiTi token contract address.
    /// @param _governor Governor contract address.
    function initialize(IERC20Upgradeable _titi, address _governor) external initializer {
        titi = _titi;
        governor = _governor;
        __ReentrancyGuard_init();
    }

    /// @notice Set new TiTi reward distributor and emit NewWorker event.
    /// @param _worker New TiTi reward distributor.
    function setWorker(address _worker) external onlyGov {
        require(_worker != address(0), "TiTiStakingV1: Zero Address");
        worker = _worker;
        emit NewWorker(_worker);
    }

    /// @notice Set new pending governor and emit NewPendingGovernor event.
    /// @param _pendingGovernor New pending governor.
    function setPendingGovernor(address _pendingGovernor) external onlyGov {
        require(_pendingGovernor != address(0), "TiTiStakingV1: Zero Address");
        pendingGovernor = _pendingGovernor;
        emit NewPendingGovernor(_pendingGovernor);
    }

    /// @notice Set new TiTiMerkleDistributor and emit NewMerkle event.
    /// @param _merkle New TiTiMerkleDistributor.
    function setMerkle(address _merkle) external onlyGov {
        require(_merkle != address(0), "TiTiStakingV1: Zero Address");
        merkle = _merkle;
        emit NewMerkle(_merkle);
    }

    /// @notice Pending governor accepts and becomes the new Governor.
    function acceptGovernor() external {
        require(msg.sender == pendingGovernor, 'TiTiStakingV1: Not Pending');
        pendingGovernor = address(0);
        address _oldAddr = governor;
        governor = msg.sender;
        emit NewGovernor(_oldAddr, msg.sender);
    }

    /// @notice Users stake TiTi into the staking pool.
    /// @param _owner Target user's address.
    /// @param _amount Target user's staking amount.
    function stake(address _owner, uint _amount) external nonReentrant {
        require(msg.sender == _owner || msg.sender == merkle, 'TiTiStakingV1: Caller not owner or merkle');
        require(_amount >= 1e18, 'TiTiStakingV1: Amount too small');
        Data storage data = users[_owner];
        if (data.status != STATUS_READY) {
            emit CancelUnbond(_owner, data.unbondTime, data.unbondShare);
            data.status = STATUS_READY;
            data.unbondTime = 0;
            data.unbondShare = 0;
        }
        titi.safeTransferFrom(_owner, address(this), _amount);
        uint share = totalTiTi == 0 ? _amount : _amount * totalShare / totalTiTi;
        totalTiTi = totalTiTi + _amount;
        totalShare = totalShare + share;
        data.share = data.share + share;
        emit Stake(_owner, share, _amount);
    }

    /// @notice Users send unbonding TiTi's request.
    /// @param _share Target user's unbonding share amount.
    function unbond(uint _share) external nonReentrant {
        Data storage data = users[msg.sender];
        if (data.status != STATUS_READY) {
            emit CancelUnbond(msg.sender, data.unbondTime, data.unbondShare);
        }
        require(_share <= data.share, 'TiTiStakingV1: Insufficient Share');
        data.status = STATUS_UNBONDING;
        data.unbondTime = block.timestamp;
        data.unbondShare = _share;
        emit Unbond(msg.sender, block.timestamp, _share);
    }

    /// @notice User withdraws unbonded TiTi from the staking pool.
    function withdraw() external nonReentrant {
        Data storage data = users[msg.sender];
        require(data.status == STATUS_UNBONDING, 'TiTiStakingV1: Not Unbonding');
        require(block.timestamp >= data.unbondTime + UNBONDING_DURATION, 'TiTiStakingV1: Not Valid Period');
        require(
            block.timestamp < data.unbondTime + UNBONDING_DURATION + WITHDRAW_DURATION,
            'TiTiStakingV1: Already Expired'
        );
        uint share = data.unbondShare;
        uint amount = totalTiTi * share / totalShare;
        totalTiTi = totalTiTi - amount;
        totalShare = totalShare - share;
        data.share = data.share - share;
        data.status = STATUS_READY;
        data.unbondTime = 0;
        data.unbondShare = 0;
        require(totalTiTi >= 1e18, 'TiTiStakingV1: Too low total titi');
        titi.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, share, amount);
    }

    /// @notice TiTi reward distributor injects TiTi and completes the reward distribution.
    /// @param _amount Distributed TiTi rewards' amount.
    function reward(uint _amount) external onlyWorker {
        require(totalShare >= 1e18, 'TiTiStakingV1: Share Too Small');
        titi.safeTransferFrom(msg.sender, address(this), _amount);
        totalTiTi = totalTiTi + _amount;
        emit Reward(msg.sender, _amount);
    }

    /// @notice Governor skims real balance and recorded value.
    /// @param _amount Skimed TiTi amount.
    function skim(uint _amount) external onlyGov {
        require(titi.balanceOf(address(this)) - _amount >= totalTiTi, 'TiTiStakingV1: Not Enough Balance');
        titi.safeTransfer(msg.sender, _amount);
        emit Skim(msg.sender, _amount);
    }

    /// @notice Get the amount of target user's staked TiTi.
    /// @param _user Target user's address.
    function getStakeValue(address _user) external view returns (uint) {
        uint share = users[_user].share;
        return share == 0 ? 0 : share * totalTiTi / totalShare;
    }
}
