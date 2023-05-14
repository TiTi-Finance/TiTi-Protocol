// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IMAMMSwapPair.sol";
import "../interfaces/ITiUSDToken.sol";
import "../interfaces/IReOrdersController.sol";
import "../interfaces/IMMFLPStakingPool.sol";

/// @title The MMF module of TiTi Protocol
/// @author TiTi Protocol
/// @notice The module implements the related functions of MMF.
/// @dev Only the owner can call the params' update function, the owner will be transferred to Timelock in the future.
contract MarketMakerFund is Ownable, ERC20Snapshot, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice USDC contract address.
    IERC20 public immutable baseToken;

    /// @notice TiUSD contract address.
    ITiUSDToken public immutable tiusdToken;

    /// @notice MAMMSwapPair contract address.
    IMAMMSwapPair public mamm;

    /// @notice ReordersController contract address.
    IReOrdersController public reordersController;

    /// @notice MMFLPStakingPool contract address.
    IMMFLPStakingPool public lpStakingPool;

    /// @notice This parameter is used for precision conversion (pegPricePrecision * baseTokenPrecision) / tiusdPrecision)
    uint public constant PRECISION_CONV = 1e6;

    /// @notice Whether to allow contracts to call the function.
    bool public isAllowedContractsCall;

    /// @notice Emitted when new MAMMSwapPair address is set.
    event NewMAMM(address oldAddr, address newAddr);

    /// @notice Emitted when new ReordersController address is set.
    event NewReordersController(address oldAddr, address newAddr);

    /// @notice Emitted when new MMFLPStakingPool address is set.
    event NewLPStakingPool(address oldAddr, address newAddr);

    /// @notice Emitted when the isAllowedContractsCall is updated.
    event IsAllowedContractsCall(bool isAllowed);

    constructor(ITiUSDToken _tiusdToken, IERC20 _baseToken) ERC20("MMF Share USDC", "mUSDC") {
        tiusdToken = _tiusdToken;
        baseToken = _baseToken;
    }

    modifier onlyEOA() {
        if (!isAllowedContractsCall) {
            require(tx.origin == msg.sender, "MarketMakerFund: Not EOA");
        }
        _;
    }

    /// @notice Set a new MAMMSwapPair contract.
    /// @param _mamm New MAMMSwapPair contract address.
    function setNewMAMM(IMAMMSwapPair _mamm) external onlyOwner {
        require(address(_mamm) != address(0), "MarketMakerFund: Cannot be address(0)");
        address oldMAMM = address(mamm);
        mamm = _mamm;
        emit NewMAMM(oldMAMM, address(_mamm));
    }

    /// @notice Set a new ReOrdersController contract.
    /// @param _reordersController New ReOrdersController contract address.
    function setNewReordersController(IReOrdersController _reordersController) external onlyOwner {
        require(address(_reordersController) != address(0), "MarketMakerFund: Cannot be address(0)");
        address oldReorders = address(reordersController);
        reordersController = _reordersController;
        emit NewReordersController(oldReorders, address(reordersController));
    }

    /// @notice Set a new MMFLPStakingPool contract.
    /// @param _lpStakingPool New MMFLPStakingPool contract address.
    function setNewLPStakingPool(IMMFLPStakingPool _lpStakingPool) external onlyOwner {
        require(address(_lpStakingPool) != address(0), "MarketMakerFund: Cannot be address(0)");
        address oldLPStakingPool = address(lpStakingPool);
        lpStakingPool = _lpStakingPool;
        _approve(address(this), address(lpStakingPool), type(uint256).max);
        emit NewLPStakingPool(oldLPStakingPool, address(_lpStakingPool));
    }

    /// @notice Set the isAllowedContractsCall.
    /// @param _isAllowed Is to allow contracts to call.
    function setIsAllowedContractsCall(bool _isAllowed) external onlyOwner {
        isAllowedContractsCall = _isAllowed;
        emit IsAllowedContractsCall(_isAllowed);
    }

    /// @notice Pause the whole system.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the whole system.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Users stake USDC to join MMF.
    /// @param amount Amount of USDC to stake.
    /// @param isStaking Whether to auto-stake the generated MMF Share Token into the MMFLPStakingPool.
    function addLiquidity(uint amount, bool isStaking) external onlyEOA nonReentrant whenNotPaused {
        reordersController.reorders();
        uint _totalSupply = totalSupply();
        (, uint256 _mmfFund1, ) = mamm.getMMFFunds();
        uint _totalFund = _mmfFund1;

        uint share = _totalSupply == 0 ? amount : amount * _totalSupply / _totalFund;
        _mint(msg.sender, share);

        uint pegPrice = reordersController.PEG_PRICE();

        uint _mintAmount = amount * pegPrice / PRECISION_CONV;
        
        tiusdToken.mint(address(mamm), _mintAmount);
        baseToken.safeTransferFrom(msg.sender, address(mamm), amount);

        mamm.addLiquidity();
        reordersController.sync();
        if (isStaking) {
            transfer(address(this), share);
            lpStakingPool.stake(share, msg.sender);
        }
    }

    /// @notice Users withdraw baseToken to exit MMF.
    /// @param share Amount of MMF Share Token to release.
    /// @param isStaking Whether part of users' MMF Share Token is staked, 
    /// if so, it will be automatically withdrawn from the MMFLPStakingPool.
    function removeLiquidity(uint share, bool isStaking) external onlyEOA nonReentrant whenNotPaused {
        reordersController.reorders();
        uint amount = getShareValue(share);
        
        if (isStaking) {
            lpStakingPool.withdraw(share, msg.sender);
            _burn(address(this), share);
        } else {
            _burn(msg.sender, share);
        }

        uint pegPrice = reordersController.PEG_PRICE();

        uint tiusdAmount = amount * pegPrice / PRECISION_CONV;
        
        uint beforeTiUSDBalance = tiusdToken.balanceOf(address(this));
        uint beforeBaseTokenBalance = baseToken.balanceOf(address(this));
        
        mamm.removeLiquidity(tiusdAmount, amount);

        uint afterTiUSDBalance = tiusdToken.balanceOf(address(this));
        uint afterBaseTokenBalance = baseToken.balanceOf(address(this));
        
        tiusdToken.burn(afterTiUSDBalance - beforeTiUSDBalance);
        baseToken.safeTransfer(msg.sender, afterBaseTokenBalance - beforeBaseTokenBalance);
        reordersController.sync();
    }

    /// @notice Users withdraw all USDC principal and TiTi rewards
    function withdrawAll() external onlyEOA nonReentrant whenNotPaused {
        uint share = balanceOf(msg.sender);
        uint stakingShare = lpStakingPool.balanceOf(msg.sender);
        uint allShare = share + stakingShare;

        _burn(msg.sender, share);

        if (stakingShare > 0) {
            lpStakingPool.withdraw(stakingShare, msg.sender);
            lpStakingPool.getReward(msg.sender);
            _burn(address(this), stakingShare);
        }

        reordersController.reorders();
        uint amount = getShareValue(allShare);
        
        uint pegPrice = reordersController.PEG_PRICE();

        uint tiusdAmount = amount * pegPrice / PRECISION_CONV;
        
        mamm.removeLiquidity(tiusdAmount, amount);
        
        tiusdToken.burn(tiusdToken.balanceOf(address(this)));
        baseToken.safeTransfer(msg.sender, baseToken.balanceOf(address(this)));
        reordersController.sync();
    }

    /// @notice Calculate total MMF Share Token's USDC value of a target user.
    /// @param account Target user's address.
    /// @return value Total USDC value.
    function getUserShareValue(address account) external view returns(uint value) {
        uint share = balanceOf(account);
        uint _totalSupply = totalSupply();
        (, uint256 _mmfFund1, ) = mamm.getMMFFunds();
        uint _totalFund = _mmfFund1;
        value = share * _totalFund / _totalSupply;
    }

    /// @notice Calculate the USDC value of a specified amount of MMF Share Token.
    /// @param share Amount of MMF Share Token to convert.
    /// @return value Total USDC value.
    function getShareValue(uint share) public view returns(uint value) {
        uint _totalSupply = totalSupply();
        (, uint256 _mmfFund1, ) = mamm.getMMFFunds();
        uint _totalFund = _mmfFund1;
        value = share * _totalFund / _totalSupply;
    }
}