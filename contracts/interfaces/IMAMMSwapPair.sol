// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IMAMMSwapPair {
    function pause() external;
    function unpause() external;
    function setNewReordersController(address _reordersController) external;
    function addLiquidity() external;
    function removeLiquidity(uint amount0, uint amount1) external;
    function sync() external;
    function mintFee() external;
    function pavAllocation(
        uint newMMFRewards0, 
        uint newMMFRewards1, 
        uint newRainyDayFunds, 
        uint newProtocolFees
    ) external;
    function migrate(address to) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function getTiUSDPrice() external view returns (uint256, bool);
    function getMMFFunds() external view returns (uint _mmfFund0, uint _mmfFund1, uint32 _blockTimestampLast);
    function getDepth() external view returns (uint112 _fund0, uint112 _fund1, uint32 _blockTimestampLast);
}
