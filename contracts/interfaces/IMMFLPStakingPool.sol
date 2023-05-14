// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IMMFLPStakingPool {
    function stake(uint256 amount, address staker) external;
    function withdraw(uint256 amount, address staker) external;
    function balanceOf(address account) external returns (uint256);
    function getReward(address staker) external;
    function pause() external;
    function unpause() external;
}
