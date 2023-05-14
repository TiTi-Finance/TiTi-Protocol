// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract IRewardDistributionRecipient is Ownable {
    address public rewardDistribution;

    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "LPStakingPool: Caller is not reward distribution");
        _;
    }

    function setRewardDistribution(address _rewardDistribution)
        external
        onlyOwner
    {
        rewardDistribution = _rewardDistribution;
    }
}

contract LPTokenWrapper {
    using SafeERC20 for IERC20;

    IERC20 public lpToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount, address staker) virtual public {
        _totalSupply = _totalSupply + amount;
        _balances[staker] = _balances[staker] + amount;
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount, address staker) virtual public {
        _totalSupply = _totalSupply - amount;
        _balances[staker] = _balances[staker] - amount;
        lpToken.safeTransfer(msg.sender, amount);
    }
}

/// @title The LP Staking Pool module of TiTi Protocol
/// @author QJ
/// @notice Users stake their LPToken to get TiTi rewards.
contract LPStakingPool is LPTokenWrapper, IRewardDistributionRecipient {
    using SafeERC20 for IERC20;

    IERC20 public immutable titi;
    uint256 public startTime;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public epochNum;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _titi, address _lpToken) {
        titi = IERC20(_titi);
        lpToken = IERC20(_lpToken);
    }

    /// @notice Start a new round of TiTi release
    /// @param _startTime Start Time in this round
    /// @param _newRewards Amount of TiTi incentives in this round
    /// @param _duration This round of TiTi incentive cycle
    function startNewEpoch(uint256 _startTime, uint256 _newRewards, uint256 _duration)
        external
        onlyRewardDistribution
        updateReward(address(0)) 
    {
        require(block.timestamp >= periodFinish, "LPStakingPool: Last Epoch is not end");
        startTime = _startTime;
        lastUpdateTime = _startTime;
        rewardRate = _newRewards / _duration;
        periodFinish = startTime + _duration;
        titi.safeTransferFrom(msg.sender, address(this), _newRewards);
        epochNum = epochNum++;
        emit RewardAdded(_newRewards);
    }

    modifier checkStart() {
        require(startTime != uint256(0), "LPStakingPool: not start");
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

    function lastTimeRewardApplicable() public view returns (uint256) {
        uint _lastTime;
        if (block.timestamp < startTime) {
            _lastTime = startTime;
        } else {
            _lastTime = Math.min(block.timestamp, periodFinish);
        }
        return _lastTime;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (
                lastTimeRewardApplicable()
                    - lastUpdateTime)
                    * rewardRate
                    * 1e18
                    / totalSupply();
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                * (rewardPerToken() - userRewardPerTokenPaid[account])
                / 1e18
                + rewards[account];
    }

    function stake(uint256 amount) external updateReward(msg.sender) checkStart {
        require(amount > 0, "LPStakingPool: Cannot stake 0");
        super.stake(amount, msg.sender);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external updateReward(msg.sender) checkStart {
        require(amount > 0, "LPStakingPool: Cannot withdraw 0");
        super.withdraw(amount, msg.sender);
        emit Withdrawn(msg.sender, amount);
    }
    
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
    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOwner {
        // cant take staked asset
        require(_token != lpToken, "LPStakingPool: Not Allow lpToken");
        // cant take reward asset
        require(_token != titi, "LPStakingPool: Not Allow titi");

        // transfer to
        _token.safeTransfer(to, amount);
    }
}
