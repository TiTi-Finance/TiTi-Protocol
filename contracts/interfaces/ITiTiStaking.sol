// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ITiTiStaking {
    function setWorker(address) external;
    function setPendingGovernor(address) external;
    function acceptGovernor() external;
    function setMerkle(address) external;
    function stake(address, uint) external;
    function unbond(uint) external;
    function withdraw() external;
    function reward(uint) external;
    function skim(uint) external;
    function extract(uint) external;
    function users(address) external view returns (uint, uint, uint, uint);
    function totalTiTi() external view returns (uint);
    function totalShare() external view returns (uint);
    function merkle() external view returns (address);
    function getStakeValue(address) external view returns (uint);
    function STATUS_READY() external view returns (uint);
    function STATUS_UNBONDING() external view returns (uint);
    function UNBONDING_DURATION() external view returns (uint);
    function WITHDRAW_DURATION() external view returns (uint);
}
