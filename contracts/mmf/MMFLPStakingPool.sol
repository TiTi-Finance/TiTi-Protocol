// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract IRewardDistributionRecipient is Ownable {
    /// @notice The address allowed to open a new reward epoch.
    address public rewardDistribution;

    /// @notice Emitted when new RewardDistribution address is set.
    event NewRewardDistribution(address oldAddr, address newAddr);

    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "MMFLPStakingPool: Caller is not reward distribution");
        _;
    }

    /// @notice Set new rewardDistribution address.
    /// @param _rewardDistribution New rewardDistribution address.
    function setRewardDistribution(address _rewardDistribution) external onlyOwner {
        require(_rewardDistribution != address(0), "MMFLPStakingPool: Cannot be address(0)");
        address _oldAddr = rewardDistribution;
        rewardDistribution = _rewardDistribution;
        emit NewRewardDistribution(_oldAddr, _rewardDistribution);
    }
}


contract LPTokenWrapper {
    using SafeERC20 for IERC20;

    /// @notice The MMF Share Token's contract address.
    IERC20 public lpToken;

    /// @notice Total staked amount.
    uint256 private _totalSupply;

    /// @notice Users' staked amount.
    mapping(address => uint256) private _balances;

    /// @notice Get total staked amount.
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Get target account's staked amount.
    /// @param account Target account's address.
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /// @notice Stake LPToken to this address and update the staked amount.
    /// @param amount Target account's staked amount.
    /// @param staker Target account's address.
    function _stake(uint256 amount, address staker) internal {
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        _totalSupply = _totalSupply + amount;
        _balances[staker] = _balances[staker] + amount;
    }

    /// @notice Withraw LPToken to user and update the staked amount.
    /// @param amount Target account's withdrawal amount.
    /// @param staker Target account's address.
    function _withdraw(uint256 amount, address staker) internal {
        _totalSupply = _totalSupply - amount;
        _balances[staker] = _balances[staker] - amount;
        lpToken.safeTransfer(msg.sender, amount);
    }
}


/// @title The LP Staking Pool module of TiTi Protocol
/// @author TiTi Protocol
/// @notice Users stake their LPToken to get TiTi rewards.
/// @dev Only the owner can call the params' update function, the owner will be transferred to Timelock in the future.
contract MMFLPStakingPool is LPTokenWrapper, IRewardDistributionRecipient {
    using SafeERC20 for IERC20;

    /// @notice TiTi contract address.
    IERC20 public immutable titi;

    /// @notice Current reward epoch's starting time.
    uint256 public startTime;

    /// @notice Current reward epoch's finishing time.
    uint256 public periodFinish;

    /// @notice Current epoch's serial number.
    uint256 public epochNum;

    /// @notice Current reward epoch's TiTi reward released amount per second.
    uint256 public rewardRate;

    /// @notice Last update timestamp. 
    uint256 public lastUpdateTime;

    /// @notice The recorded total amount of TiTi reward accumulated by each staked MMF Share Token.
    uint256 public rewardPerTokenStored;

    /// @notice The users' total paid amount of TiTi reward accumulated by each staked MMF Share Token.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice The users' total amount of TiTi reward records.
    mapping(address => uint256) public rewards;

    /// @notice Emitted when start a new reward epoch and add new TiTi rewards.
    event RewardAdded(uint256 reward);

    /// @notice Emitted when a user stakes MMF Share Token.
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user withraws MMF Share Token.
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims the TiTi rewards.
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _titi, address _lpToken) {
        titi = IERC20(_titi);
        lpToken = IERC20(_lpToken);
    }

    modifier onlyMMF() {
        require(msg.sender == address(lpToken), "MMFLPStakingPool: Not Matched MMF");
        _;
    }

    modifier checkStart() {
        require(startTime != uint256(0), "MMFLPStakingPool: Not start");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /// @notice Start a new TiTi rewards epoch.
    /// @param _startTime Starting time of the epoch.
    /// @param _newRewards Current epoch's TiTi rewards amount.
    /// @param _duration Current TiTi rewards epoch duration.
    function startNewEpoch(uint256 _startTime, uint256 _newRewards, uint256 _duration)
        external
        onlyRewardDistribution
        updateReward(address(0)) 
    {
        require(block.timestamp >= periodFinish, "MMFLPStakingPool: Last Epoch is not end");

        titi.safeTransferFrom(msg.sender, address(this), _newRewards);

        startTime = _startTime;
        lastUpdateTime = _startTime;
        rewardRate = _newRewards / _duration;
        periodFinish = startTime + _duration;
        epochNum = epochNum++;
        emit RewardAdded(_newRewards);
    }

    /// @notice Stake MMF Share Token and update the staked amount.
    /// @dev This interface only allows MarketMakerFund to call for automation.
    /// @param amount Target account's staked amount.
    /// @param staker Target account's address.
    function stake(uint256 amount, address staker) external onlyMMF updateReward(staker) checkStart {
        require(amount > 0, "MMFLPStakingPool: Cannot stake 0");
        _stake(amount, staker);
        emit Staked(staker, amount);
    }

    /// @notice Withdraw MMF Share Token and update the staked amount.
    /// @dev This interface only allows MarketMakerFund to call for automation.
    /// @param amount Target account's withdrawal amount.
    /// @param staker Target account's address.
    function withdraw(uint256 amount, address staker) external onlyMMF updateReward(staker) checkStart {
        require(amount > 0, "MMFLPStakingPool: Cannot withdraw 0");
        _withdraw(amount, staker);
        emit Withdrawn(staker, amount);
    }

    /// @notice Claim all TiTi rewards.
    /// @dev This interface only allows MarketMakerFund to call for automation.
    /// @param staker Target account's address.
    function getReward(address staker) external updateReward(staker) onlyMMF checkStart {
        uint256 reward = rewards[staker];
        if (reward > 0) {
            rewards[staker] = 0;
            titi.safeTransfer(staker, reward);
            emit RewardPaid(staker, reward);
        }
    }

    /// @notice Stake MMF Share Token and update the staked amount.
    /// @param amount Target account's staked amount.
    function stake(uint256 amount) external updateReward(msg.sender) checkStart {
        require(amount > 0, "MMFLPStakingPool: Cannot stake 0");
        _stake(amount, msg.sender);
        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraw MMF Share Token and update the staked amount.
    /// @param amount Target account's withdrawal amount.
    function withdraw(uint256 amount) external updateReward(msg.sender) checkStart {
        require(amount > 0, "MMFLPStakingPool: Cannot withdraw 0");
        _withdraw(amount, msg.sender);
        emit Withdrawn(msg.sender, amount);
    }
    
    /// @notice Claim all TiTi rewards.
    function getReward() external updateReward(msg.sender) checkStart {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            titi.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice This function allows governance to take unsupported tokens out of the
    // contract, since this one exists longer than the other pools.
    // This is in an effort to make someone whole, should they seriously
    // mess up. There is no guarantee governance will vote to return these.
    // It also allows for removal of airdropped tokens.
    /// @param _token Target recover token's address.
    /// @param amount Target recover token's amount.
    /// @param to Received address.
    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOwner {
        // cant take staked asset
        require(_token != lpToken, "MMFLPStakingPool: Not Allow lpToken");
        // cant take reward asset
        require(_token != titi, "MMFLPStakingPool: Not Allow titi");

        // transfer to
        _token.safeTransfer(to, amount);
    }

    /// @notice Get the latest reward calculation applicable time.
    function lastTimeRewardApplicable() public view returns (uint256) {
        uint _lastTime;
        if (block.timestamp < startTime) {
            _lastTime = startTime;
        } else {
            _lastTime = Math.min(block.timestamp, periodFinish);
        }
        return _lastTime;
    }

    /// @notice Get unrecorded total amount of TiTi reward accumulated by each staked LPToken.
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored + (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalSupply();
    }

    /// @notice Get target user's claimable TiTi rewards.
    function earned(address account) public view returns (uint256) {
        return balanceOf(account) * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }
}
