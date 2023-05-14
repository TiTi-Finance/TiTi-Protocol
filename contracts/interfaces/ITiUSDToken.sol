// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ITiUSDToken {
    function mint(address account, uint amount) external;
    function burn(uint amount) external;
    function reorders(address pair, bool isPositive, uint amount) external;
    function setNewCoreController(address _CoreController) external;
    function balanceOf(address account) external view returns (uint256);
}
