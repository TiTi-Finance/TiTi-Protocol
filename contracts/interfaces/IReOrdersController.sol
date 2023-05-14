// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IReOrdersController {
    function sync() external;
    function pause() external;
    function unpause() external;
    function setNewMAMM(address _mamm) external;
    function setNewMMF(address _mmf) external;
    function setNewPegPrice(uint256 _pegPrice) external;
    function setNewDuration(uint256 _duration) external;
    function setNewAllocation(
        uint256 _mmfRewardsAllocation, 
        uint256 _rainyDayFundAllocation, 
        uint256 _protocolFeeAllocation,
        address _rainyDayFundVault, 
        address _protocolFeeVault
    ) external;
    function setNewCoreController(address _coreController) external;
    function reorders() external;
    function rainyDayFundVault() external view returns (address);
    function protocolFeeVault() external view returns (address);
    function PEG_PRICE() external view returns (uint256 _pegPrice);
}
