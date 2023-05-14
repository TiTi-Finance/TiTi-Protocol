// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../oracles/TiTiOracles.sol";
import "../libraries/Babylonian.sol";
import "../libraries/UQ112x112.sol";
import '../interfaces/IReOrdersController.sol';

/// @title The MAMM module of TiTi Protocol
/// @author TiTi Protocol
/// @notice The module implements the related functions of MAMM.
/// @dev Only the owner can call the params' update function, the owner will be transferred to Timelock in the future.
contract MAMMSwapPair is Ownable, Pausable, TiTiOracles, ReentrancyGuard {
    using UQ112x112 for uint224;
    using SafeERC20 for IERC20;

    /// @notice MAX_UINT112.
    uint112 private constant MAX_UINT112 = type(uint112).max;

    /// @notice MarketMakerFund contract address.
    address public immutable mmf;

    /// @notice ReOrdersController contract address.
    address public reordersController;

    /// @notice The address used to receive swap fees.
    address public feeTo;

    /// @notice Whether to charge swap fees.
    bool public feeOn;

    /// @notice TiUSD contract address.
    IERC20 public immutable token0;

    /// @notice USDC contract address.
    IERC20 public immutable token1;

    /// @notice TiUSD balance.
    uint112 private fund0;       

    /// @notice USDC balance.    
    uint112 private fund1;

    /// @notice Last update timestamp. 
    uint32  private blockTimestampLast;

    /// @notice Last MMF's TiUSD staked amount in MAMM.
    uint private mmfFund0;

    /// @notice Last MMF's USDC staked amount in MAMM.
    uint private mmfFund1;
    
    /// @notice fund0 * fund1, as of immediately after the most recent liquidity event.
    uint public kLast;

    /// @notice Whether to allow contracts to call the function.
    bool public isAllowedContractsCall;

    /// @notice Emitted when users add liquidity through MarketMakerFund.
    event AddLiquidity(uint amount0, uint amount1);

    /// @notice Emitted when users remove liquidity through MarketMakerFund.
    event RemoveLiquidity(uint amount0, uint amount1);

    /// @notice Emitted when users mint TiUSD.
    event Mint(address indexed sender, uint baseTokenAmount, uint tiusdAmount);

    /// @notice Emitted when users redeem USDC.
    event Redeem(address indexed sender, uint baseTokenAmount, uint tiusdAmount);

    /// @notice Emitted when the fund0 and fund1 are updated.
    event Sync(uint112 fund0, uint112 fund1);

    /// @notice Emitted when new reordersController is set.
    event NewReordersController(address oldAddr, address newAddr);

    /// @notice Emitted when new feeTo address is set.
    event NewFeeTo(address oldFeeTo, address newFeeTo);

    /// @notice Emitted when new twap period is set.
    event NewTWAPPeriod(uint256 period);

    /// @notice Emitted when the isAllowedContractsCall is updated.
    event IsAllowedContractsCall(bool isAllowed);

    /// @notice Emitted when PAV allocation is triggered.
    event PAVAllocation(
        uint mmfRewards,
        uint rainyDayFunds,
        uint protocolFees,
        uint blockTimestampLast
    );

    constructor(
        IERC20 _token0,
        IERC20 _token1,
        address _mmf
    ) {
        token0 = _token0;
        token1 = _token1;
        mmf = _mmf;
    }

    modifier onlyEOA() {
        if (!isAllowedContractsCall) {
            require(tx.origin == msg.sender, "MAMMSwapPair: Not EOA");
        }
        _;
    }

    modifier onlyReordersController() {
        require(msg.sender == reordersController, "MAMMSwapPair: Not ReordersController");
        _;
    }

    modifier onlyMMF() {
        require(msg.sender == mmf, "MAMMSwapPair: Not Matched MMF");
        _;
    }

    /// @notice Set a new address to receive swap fees.
    /// @param _feeTo New address to receive swap fees.
    function setFeeTo(address _feeTo) external onlyOwner {
        address oldFeeTo = feeTo;
        feeTo = _feeTo;
        feeOn = feeTo != address(0);
        emit NewFeeTo(oldFeeTo, _feeTo);
    }

    /// @notice Set a new period for the TWAP window.
    /// @param _period New period for the TWAP window.
    function setPeriod(uint256 _period) external onlyOwner {
        require(_period != 0, "MAMMSwapPair: Cannot be zero");
        period = _period;
        emit NewTWAPPeriod(_period);
    }

    /// @notice Set the isAllowedContractsCall.
    /// @param _isAllowed Is to allow contracts to call.
    function setIsAllowedContractsCall(bool _isAllowed) external onlyOwner {
        isAllowedContractsCall = _isAllowed;
        emit IsAllowedContractsCall(_isAllowed);
    }

    /// @notice Set a new ReOrdersController contract.
    /// @param _reordersController New ReOrdersController contract address.
    function setNewReordersController(address _reordersController) external onlyOwner {
        require(_reordersController != address(0), "MAMMSwapPair: Cannot be address(0)");
        address oldReorders = reordersController;
        reordersController = _reordersController;
        emit NewReordersController(oldReorders, _reordersController);
    }

    /// @notice Receive swap fees.
    /// @dev Only ReOrdersController can call this function
    /// Since ReOrders will change K, it is necessary to complete the collection of the previous round of swap fee
    /// before executing ReOrders each time.
    function mintFee() external nonReentrant onlyReordersController {
        uint _kLast = kLast; // gas savings
        uint112 _fund0 = fund0;
        uint112 _fund1 = fund1;
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Babylonian.sqrt(uint(_fund0) * uint(_fund1));
                uint rootKLast = Babylonian.sqrt(_kLast);
                // When the swap fee is turned on, all swap fees will be included in the protocol fee
                if (rootK > rootKLast) {
                    uint amount0 = uint(_fund0) * (rootK - rootKLast) / rootK;
                    uint amount1 = uint(_fund1) * (rootK - rootKLast) / rootK;
                    token0.safeTransfer(feeTo, amount0);
                    token1.safeTransfer(feeTo, amount1);
                    
                    uint balance0 = token0.balanceOf(address(this));
                    uint balance1 = token1.balanceOf(address(this));

                    _update(balance0, balance1, _fund0, _fund1);
                    kLast = uint(fund0) * fund1; // fund0 and fund1 are up-to-date
                    
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    /// @notice Users add liquidity through MarketMakerFund.
    /// @dev Only MMF can call this function.
    function addLiquidity() external nonReentrant onlyMMF {
        uint112 _fund0 = fund0;
        uint112 _fund1 = fund1;
        uint balance0 = token0.balanceOf(address(this));
        uint balance1 = token1.balanceOf(address(this));
        uint amount0 = balance0 - _fund0;
        uint amount1 = balance1 - _fund1;

        mmfFund0 += amount0;
        mmfFund1 += amount1;

        _update(balance0, balance1, _fund0, _fund1);

        if (feeOn) 
            kLast = uint(fund0) * fund1;

        emit AddLiquidity(amount0, amount1);
    }

    /// @notice Users remove liquidity through MarketMakerFund.
    /// @dev Only MMF can call this function.
    function removeLiquidity(uint _amount0, uint _amount1) external nonReentrant onlyMMF {
        uint112 _fund0 = fund0;
        uint112 _fund1 = fund1;
        IERC20 _token0 = token0;
        IERC20 _token1 = token1;
        
        _token0.safeTransfer(mmf, _amount0);
        _token1.safeTransfer(mmf, _amount1);

        uint balance0 = _token0.balanceOf(address(this));
        uint balance1 = _token1.balanceOf(address(this));

        mmfFund0 = mmfFund0 - _amount0;
        mmfFund1 = mmfFund1 - _amount1;

        _update(balance0, balance1, _fund0, _fund1);

        if (feeOn) 
            kLast = uint(fund0) * fund1;
        
        emit RemoveLiquidity(_amount0, _amount1);
    }

    /// @notice Users mint TiUSD by USDC.
    /// @param _amount Amount of USDC spent by users.
    function mint(uint256 _amount) external onlyEOA nonReentrant whenNotPaused {
        (uint256 _fund0, uint256 _fund1,) = getDepth();
        uint256 tiusdOut = _getAmountOut(_amount, _fund1, _fund0);
        token1.safeTransferFrom(msg.sender, address(this), _amount);
        _swap(tiusdOut, 0, msg.sender);   
        emit Mint(msg.sender, _amount, tiusdOut);
    }

    /// @notice Users redeem USDC by TiUSD.
    /// @param _amount Amount of TiUSD spent by users.
    function redeem(uint256 _amount) external onlyEOA nonReentrant whenNotPaused {
        (uint256 _fund0, uint256 _fund1,) = getDepth();
        uint256 baseTokenOut = _getAmountOut(_amount, _fund0, _fund1);
        token0.safeTransferFrom(msg.sender, address(this), _amount);
        _swap(0, baseTokenOut, msg.sender);
        emit Redeem(msg.sender, baseTokenOut, _amount);
    }

    /// @notice Match the requirements of reorders and update the global parameters.
    function sync() external nonReentrant whenNotPaused onlyReordersController {
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)), fund0, fund1);
        if (feeOn) kLast = uint(fund0) * fund1;
        _resetPrice();
    }

    /// @notice Update global parameters based on the latest balance.
    function updateOraclePrice() external nonReentrant whenNotPaused {
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)), fund0, fund1);
    }

    /// @notice Allocate PAV funds, this function is called by OrdersController in _reorders(), and its purpose is as follows:
    /// 1. It is used to complete the profit sharing for MMF participants. Since the total amount of shares is recorded in MMF, 
    /// only mmfFund0 and mmfFund1 need to be updated to distribute profits to participants;
    /// 2. Used to transfer part of USDC to rainyDayFund
    /// 3. Used to transfer part of USDC to protocolFeeVault
    /// @param _newMMFRewards0 The amount of TiUSD that needs to be allocated to MMF in PAV.
    /// @param _newMMFRewards1 The amount of USDC that needs to be allocated to MMF in PAV.
    /// @param _newRainyDayFunds The amount of USDC that needs to be withdrawn for rainy day fund in PAV.
    /// @param _newProtocolFees The amount of USDC that needs to be withdrawn for protocol fee in PAV.
    function pavAllocation(   
        uint _newMMFRewards0, 
        uint _newMMFRewards1, 
        uint _newRainyDayFunds, 
        uint _newProtocolFees
    ) 
        external 
        nonReentrant 
        onlyReordersController 
        whenNotPaused 
    {
        IERC20 _token = token1;
        uint newMMFRewards = _newMMFRewards1;
        // Since MMF is recorded by share, we can update mmfFund directly to complete the profit sharing
        mmfFund0 = mmfFund0 + _newMMFRewards0;
        mmfFund1 = mmfFund1 + _newMMFRewards1;

        address _rainyDayFundVault = IReOrdersController(reordersController).rainyDayFundVault();
        address _protocolFeeVault = IReOrdersController(reordersController).protocolFeeVault();
        
        _token.safeTransfer(_rainyDayFundVault, _newRainyDayFunds);
        _token.safeTransfer(_protocolFeeVault, _newProtocolFees);
        
        emit PAVAllocation(newMMFRewards, _newRainyDayFunds, _newProtocolFees, block.timestamp);
    }

    /// @notice Pause the whole system.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the whole system.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Get the lastest MMF's TiUSD and USDC staked amount in MAMM.
    function getMMFFunds() external view returns (uint, uint, uint32) {
        return (mmfFund0, mmfFund1, blockTimestampLast);
    }

    /// @notice Get TiUSD's average price denominated in USDC.
    /// @return tiusdPriceMantissa TiUSD price with 18-bit precision.
    /// @return isValid Whether the return TiUSD price is valid.
    function getTiUSDPrice() external view whenNotPaused returns (uint256 tiusdPriceMantissa, bool isValid) {
        (tiusdPriceMantissa, isValid) = _getTiUSDPrice();
    }

    /// @notice Get the lastest MAMM's TiUSD and USDC depth.
    function getDepth() public view returns (uint112, uint112, uint32) {
        return (fund0, fund1, blockTimestampLast);
    }

    /// @notice Perform swap operation
    /// @dev this low-level function should be called from a contract which performs important safety checks
    function _swap(uint _amount0Out, uint _amount1Out, address _to) internal {
        require(_amount0Out > 0 || _amount1Out > 0, 'MAMMSwapPair: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _fund0, uint112 _fund1,) = getDepth(); // gas savings

        // Redeem cannot lose MMF's Fund, because currently MMF's Fund is only used to increase depth
        bool isSufficient = _amount0Out <= _fund0 && _amount1Out <= uint(_fund1) - mmfFund1;

        require(isSufficient, 'MAMMSwapPair: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
            IERC20 _token0 = token0;
            IERC20 _token1 = token1;
            require(_to != address(_token0) && _to != address(_token1) && _to != address(this), 'MAMMSwapPair: INVALID_TO');

            if (_amount0Out > 0) _token0.safeTransfer(_to, _amount0Out);
            if (_amount1Out > 0) _token1.safeTransfer(_to, _amount1Out);

            balance0 = _token0.balanceOf(address(this));
            balance1 = _token1.balanceOf(address(this));
        }

        uint amount0In = balance0 > _fund0 - _amount0Out ? balance0 - (_fund0 - _amount0Out) : 0;
        uint amount1In = balance1 > _fund1 - _amount1Out ? balance1 - (_fund1 - _amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'MAMMSwapPair: INSUFFICIENT_INPUT_AMOUNT');
        
        { // scope for funds{0,1}Adjusted, avoids stack too deep errors
            uint balance0Adjusted = balance0 * 1000 - (amount0In * 3);
            uint balance1Adjusted = balance1 * 1000 - (amount1In * 3);
            require(balance0Adjusted * balance1Adjusted >= uint(_fund0) * uint(_fund1) * 1000**2, 'MAMMSwapPair: K');
        }

        _update(balance0, balance1, _fund0, _fund1);   
    }
    
    /// @notice According to k = x * y, calculate the amount of tokenOut obtained in the swap process.
    function _getAmountOut(
        uint _amountIn,
        uint _fundIn,
        uint _fundOut
    )
        internal
        pure
        returns (uint amountOut)
    {
       require(_amountIn > 0, 'MAMMSwapPair: INSUFFICIENT_INPUT_AMOUNT');
       require(_fundIn > 0 && _fundOut > 0, 'MAMMSwapPair: INSUFFICIENT_LIQUIDITY');
       uint amountInWithFee = _amountIn * 997;
       uint numerator = amountInWithFee * _fundOut;
       uint denominator = _fundIn * 1000 + amountInWithFee;
       amountOut = numerator / denominator;
    }

    function _update(uint _balance0, uint _balance1, uint112 _fund0, uint112 _fund1) private {
        require(_balance0 <= MAX_UINT112 && _balance1 <= MAX_UINT112, 'MAMMSwapPair: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);

        unchecked {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

            if (timeElapsed > 0 && _fund0 != 0 && _fund1 != 0) {

                // * never overflows, and + overflow is desired
                price0CumulativeLast += uint(UQ112x112.encode(_fund1).uqdiv(_fund0)) * timeElapsed;
                price1CumulativeLast += uint(UQ112x112.encode(_fund0).uqdiv(_fund1)) * timeElapsed;
                
            }
        }
        // Update TiUSD's TWAP
        _updatePrice(blockTimestamp);

        fund0 = uint112(_balance0);
        fund1 = uint112(_balance1);
        blockTimestampLast = blockTimestamp;

        emit Sync(fund0, fund1);
    }
}
