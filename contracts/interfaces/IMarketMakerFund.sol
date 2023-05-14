// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IMarketMakerFund {
    function pause() external;
    function unpause() external;
    function setNewReordersController(address _reordersController) external;
    function setNewCoreController(address _CoreController) external;
    function addLiquidity(uint amount, bool isStaking) external;
    function removeLiquidity(uint share) external;
}
