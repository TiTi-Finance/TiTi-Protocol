// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IMerkleDistributor {
    function updateMerkleRoot(bytes32 _root) external;
    function updateStaking(address _staking) external;
    function deposit(uint _amount) external;
    function claimAndStake(uint _reward, bytes32[] calldata _proof) external;
    function claim(uint _reward, bytes32[] calldata _proof) external;
    function claimed(address _user) external view returns (uint amount);
}
