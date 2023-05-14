// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMAMMSwapPair.sol";
import "../interfaces/ITiUSDToken.sol";

/// @title The control module of reorders in TiTi Protocol
/// @author TiTi Protocol
/// @notice This module implements and manages the ReOrders function.
/// @dev Only the owner can call the params' update function, and the owner will be transferred to Timelock in the future.
contract ReOrdersController is Ownable, ReentrancyGuard, Pausable {
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice USDC contract address.
    IERC20 public immutable baseToken;

    /// @notice TiUSD contract address.
    ITiUSDToken public immutable tiusdToken;

    /// @notice MAMMSwapPair contract address.
    IMAMMSwapPair public immutable mamm;

    /// @notice MarketMakerFund contract address.
    address public immutable mmf;

    /// @notice Used to manage accumulated rainy day fund.
    address public rainyDayFundVault;

    /// @notice Used to manage accumulated protocol fee.
    address public protocolFeeVault;

    /// @notice The time period that triggers reorders.
    uint256 public duration = 12 hours;

    /// @notice The maximum TiUSD/USDC price spread that triggers reorders.
    int256 public priceDelta = 0.05e18;

    /// @notice PegPrice's precision.
    int256 public constant PRICE_PRECISION = 1e18;

    /// @notice When there is only USDC in the reserve, the peg price is $1. In the future, 
    /// it will be dynamically calculated based on the reserve ratio.
    int256 public constant PEG_PRICE = 1e18;

    /// @notice To normalize USDC and TiUSD units.
    int256 public constant PRECISION_CONV = 1e12;

    /// @notice The balance of TiUSD in MAMMSwapPair recorded during the last reorders.
    int256 public lastFund0;

    /// @notice The balance of USDC in MAMMSwapPair recorded during the last reorders.
    int256 public lastFund1;

    /// @notice Last reorders' timestamp.
    uint256 public lastReordersTime;

    /// @notice Percentage of PAV allocated to MMF participants.
    uint256 public mmfRewardsAllocation = 0.2e18;

    /// @notice Percentage of PAV allocated to rainy day fund.
    uint256 public rainyDayFundAllocation = 0.4e18;

    /// @notice Percentage of PAV allocated to protocol fee.
    uint256 public protocolFeeAllocation = 0.4e18;

    /// @notice Conditions that trigger reorders.
    enum ReOrdersCondition { Period, PriceSpread, MMF }

    /// @notice Emitted when reorders is triggered.
    event ReOrders(ReOrdersCondition reordersCondition, uint pavAmount, uint lastReordersTime);

    /// @notice Emitted when new priceDelta is set.
    event NewPriceDelta(int256 oldPriceDelta, int256 newPriceDelta);

    /// @notice Emitted when new reorders duration is set.
    event NewDuration(uint oldDuration, uint newDuration);

    /// @notice Emitted when new PAV allocation params is set.
    event NewAllocation(
        uint mmfRewardsAllocation, 
        uint rainyDayFundsAllocation, 
        uint protocolFeesAllocation, 
        address rainyDayFundVault, 
        address protocolFeeVault
    );

    constructor(
        ITiUSDToken _tiusdToken,
        IERC20 _baseToken,
        IMAMMSwapPair _mamm,
        address _mmf,
        address _rainyDayFundVault,
        address _protocolFeeVault
    ) {
        tiusdToken = _tiusdToken;
        baseToken = _baseToken;
        mamm = _mamm;
        mmf = _mmf;
        rainyDayFundVault = _rainyDayFundVault;
        protocolFeeVault = _protocolFeeVault;
        lastReordersTime = block.timestamp;
    }

    modifier onlyMMF() {
        require(msg.sender == mmf, "ReOrdersController: Not Matched MMF");
        _;
    }

    /// @notice Set new priceDelta and emit NewPriceDelta event.
    /// @param _priceDelta New price delta.
    function setNewPriceDelta(int256 _priceDelta) external onlyOwner {
        require(_priceDelta != int256(0), "ReOrdersController: Cannot be zero");
        int256 oldPriceDelta = priceDelta;
        priceDelta = _priceDelta;
        emit NewPriceDelta(oldPriceDelta, _priceDelta);
    }

    /// @notice Set new reorders duration and emit NewDuration event.
    /// @param _duration New reorders duration.
    function setNewDuration(uint256 _duration) external onlyOwner {
        require(_duration != uint256(0), "ReOrdersController: Cannot be zero");
        uint oldDuration = duration;
        duration = _duration;
        emit NewDuration(oldDuration, _duration);
    }

    /// @notice Set new PAV allocation params and emit NewAllocation event.
    /// @param _mmfRewardsAllocation Percentage of PAV allocated to MMF participants.
    /// @param _rainyDayFundAllocation Percentage of PAV allocated to rainy day fund.
    /// @param _protocolFeeAllocation Percentage of PAV allocated to protocol fee.
    /// @param _rainyDayFundVault New rainy day fund vault address.
    /// @param _protocolFeeVault New protocol fee vault address.
    function setNewAllocation(
        uint256 _mmfRewardsAllocation, 
        uint256 _rainyDayFundAllocation, 
        uint256 _protocolFeeAllocation,
        address _rainyDayFundVault, 
        address _protocolFeeVault
    ) 
        external 
        onlyOwner
    {
        require(_rainyDayFundVault != address(0), "ReOrdersController: Cannot be address(0)");
        require(_protocolFeeVault != address(0), "ReOrdersController: Cannot be address(0)");

        uint256 totalAllocation = _mmfRewardsAllocation + _rainyDayFundAllocation + _protocolFeeAllocation;

        require(totalAllocation == 1e18, "ReOrdersController: totalAllocation must be 100%");

        mmfRewardsAllocation = _mmfRewardsAllocation;
        rainyDayFundAllocation = _rainyDayFundAllocation;
        protocolFeeAllocation = _protocolFeeAllocation;
        rainyDayFundVault = _rainyDayFundVault;
        protocolFeeVault = _protocolFeeVault;

        emit NewAllocation(
            _mmfRewardsAllocation, 
            _rainyDayFundAllocation, 
            _protocolFeeAllocation, 
            _rainyDayFundVault, 
            _protocolFeeVault
        );
    }

    /// @notice Used by MMF to update the latest MAMM balance after completing liquidity provision or withdrawal.
    function sync() external nonReentrant whenNotPaused onlyMMF {
        (uint256 _newfund0, uint256 _newfund1,)= mamm.getDepth();
        lastFund0 = _newfund0.toInt256();
        lastFund1 = _newfund1.toInt256();
    }

    /// @notice Pause the whole system.
    function pause() external nonReentrant onlyOwner {
        _pause();
    }

    /// @notice Unpause the whole system.
    function unpause() external nonReentrant onlyOwner {
        _unpause();
    }

    /// @notice Trigger reorders, adjust the TiUSD/USDC price in MAMM, and complete PAV allocation.
    function reorders() external nonReentrant whenNotPaused {
        uint256 nowTime = block.timestamp;
        ReOrdersCondition reordersCondition;
        
        // There are three trigger conditions for ReOrders:
        //      * When there is any update operation in MMF, reorders will be triggered automatically;
        //      * Fixed time period trigger;
        //      * Fixed spread trigger.
        if (msg.sender == mmf) {
            reordersCondition = ReOrdersCondition.MMF;
        } else if (nowTime >= lastReordersTime + duration) {
            reordersCondition = ReOrdersCondition.Period;
        } else {
            (uint256 _twap, bool _isValid) = mamm.getTiUSDPrice();
            require(_isValid, "ReOrdersController: Oracle Not Valid");

            int256 twap = _twap.toInt256();
            if (twap - PEG_PRICE > priceDelta || twap - PEG_PRICE < -priceDelta) {
                reordersCondition = ReOrdersCondition.PriceSpread;
            } else {
                revert("ReOrdersController: Do not meet any condition");
            }
        }

        uint256 pavAmount = _reorders();
        emit ReOrders(reordersCondition, pavAmount, lastReordersTime);
    }

    function _reorders() internal returns(uint) {
        // First complete the collection of swap fee, because ReOrders will change K in an unconventional way.
        mamm.mintFee();

        (uint256 _fund0, uint256 _fund1,)= mamm.getDepth();
        int256 _fund0Conv = _fund0.toInt256();
        int256 _fund1Conv = _fund1.toInt256();
        int256 _lastFund0 = lastFund0;
        int256 _lastFund1 = lastFund1;
        uint256 pavAmount;

        // scope for _fund{A,B} and _lastFund{A,B}, avoids stack too deep errors.
        {
            // Calculate the current round of PAV and the amount of TiUSD that requires mint or burn, 
            // The calculation method is detailed in the white paper:
            //      * ΔPAV_{n} = (X_{n}} - X_{n-1}) - (Y_{n-1} - Y_{n}) * PegPrice_{n}

            // _fundA is the remaining TiUSD in MAMM, _fundB is the remaining USDC in MAMM.

            int256 _fundA = _fund0Conv;
            int256 _fundB = _fund1Conv * PRECISION_CONV;
            int256 _lastFundA = _lastFund0;
            int256 _lastFundB = _lastFund1 * PRECISION_CONV;

            int256 _pavAmount = ((_fundB - _lastFundB) - (_lastFundA - _fundA) * PEG_PRICE / PRICE_PRECISION) / PRECISION_CONV;
            pavAmount = _pavAmount.toUint256();
        }
        
        // Calculate and execute PAV allocation
        if (pavAmount > 0) {
            uint256 newMMFRewards = pavAmount * mmfRewardsAllocation / 1e18;
            uint256 _newMMFRewards0 = newMMFRewards * uint256(PRECISION_CONV);
            uint256 _newMMFRewards1 = newMMFRewards;
            uint256 _newRainyDayFunds = pavAmount * rainyDayFundAllocation / 1e18;
            // Avoid rounding error
            uint256 _newProtocolFees = pavAmount - newMMFRewards - _newRainyDayFunds;

            mamm.pavAllocation(
                _newMMFRewards0,
                _newMMFRewards1, 
                _newRainyDayFunds, 
                _newProtocolFees
            );

            uint256 _balance0 = baseToken.balanceOf(address(mamm));
            uint256 _balance1 = tiusdToken.balanceOf(address(mamm));
            (uint256 _changeAmount, bool isPositive) = _balance0 * uint256(PRECISION_CONV) > _balance1 ? 
                (_balance0 * uint256(PRECISION_CONV) - _balance1, true) : (_balance1 - _balance0 *  uint256(PRECISION_CONV), false);
            tiusdToken.reorders(address(mamm), isPositive, _changeAmount);
        }
        
        mamm.sync();
        (uint256 _newfund0, uint256 _newfund1,)= mamm.getDepth();
        lastFund0 = _newfund0.toInt256();
        lastFund1 = _newfund1.toInt256();
        lastReordersTime = block.timestamp;
        return pavAmount;
    }
}