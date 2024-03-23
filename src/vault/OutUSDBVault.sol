//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {BlastModeEnum} from "../blast/BlastModeEnum.sol";
import "../blast/IERC20Rebasing.sol";
import "../stake/interfaces/IRUSDStakeManager.sol";
import "../utils/Initializable.sol";
import "../token/USDB//interfaces/IRUSD.sol";
import "./interfaces/IOutUSDBVault.sol";
import "./interfaces/IOutFlashCallee.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @title USDB Vault Contract
 */
contract OutUSDBVault is IOutUSDBVault, ReentrancyGuard, Initializable, Ownable, BlastModeEnum {
    using SafeERC20 for IERC20;

    address public constant USDB = 0x4200000000000000000000000000000000000022;
    uint256 public constant RATIO = 10000;
    address public immutable RUSD;

    address private _RUSDStakeManager;
    address private _revenuePool;
    uint256 private _protocolFee;
    FlashLoanFee private _flashLoanFee;

    uint256 public y = 100;

    modifier onlyRUSDContract() {
        if (msg.sender != RUSD) {
            revert PermissionDenied();
        }
        _;
    }

    /**
     * @param owner - Address of the owner
     * @param rusd - Address of RUSD Token
     */
    constructor(
        address owner,
        address rusd
    ) Ownable(owner) {
        RUSD = rusd;
    }

    /** view **/
    function RUSDStakeManager() external view returns (address) {
        return _RUSDStakeManager;
    }

    function revenuePool() external view returns (address) {
        return _revenuePool;
    }

    function protocolFee() external view returns (uint256) {
        return _protocolFee;
    }

    function flashLoanFee() external view returns (FlashLoanFee memory) {
        return _flashLoanFee;
    }

    /** function **/
    /**
     * @dev Initializer
     * @param stakeManager_ - Address of RUSDStakeManager
     * @param revenuePool_ - Address of revenue pool
     * @param protocolFee_ - Protocol fee rate
     * @param providerFeeRate_ - Flashloan provider fee rate
     * @param protocolFeeRate_ - Flashloan protocol fee rate
     */
    function initialize(
        address stakeManager_, 
        address revenuePool_, 
        uint256 protocolFee_, 
        uint256 providerFeeRate_, 
        uint256 protocolFeeRate_
    ) external override initializer {
        IERC20Rebasing(USDB).configure(YieldMode.CLAIMABLE);
        setRUSDStakeManager(stakeManager_);
        setRevenuePool(revenuePool_);
        setProtocolFee(protocolFee_);
        setFlashLoanFee(providerFeeRate_, protocolFeeRate_);
    }

    /**
     * @dev When user withdraw by RUSD contract
     * @param user - Address of User
     * @param amount - Amount of USDB for withdraw
     */
    function withdraw(address user, uint256 amount) external override onlyRUSDContract {
        IERC20(USDB).safeTransfer(user, amount);
    }

    /**
     * @dev Claim USDB yield to this contract
     */
    function claimUSDBYield() public override returns (uint256) {
        // y = y + 1;
        // console.log("claimUSDBYield y:", y);
        uint256 nativeYield = IERC20Rebasing(USDB).getClaimableAmount(address(this));
        if (nativeYield > 0) {
            IERC20Rebasing(USDB).claim(address(this), nativeYield);
            if (_protocolFee > 0) {
                uint256 feeAmount;
                unchecked {
                    feeAmount = nativeYield * _protocolFee / RATIO;
                }
                IERC20(USDB).safeTransfer(_revenuePool, feeAmount);
                unchecked {
                    nativeYield -= feeAmount;
                }
            }

            IRUSD(RUSD).mint(_RUSDStakeManager, nativeYield);
            IRUSDStakeManager(_RUSDStakeManager).updateYieldPool(nativeYield);
        

            emit ClaimUSDBYield(nativeYield);
        }

        //return nativeYield;
        emit ClaimUSDBYield(nativeYield);
        return nativeYield;
    }

     /**
     * @dev Outrun USDB FlashLoan service
     * @param receiver - Address of receiver
     * @param amount - Amount of USDB loan
     * @param data - Additional data
     */
    function flashLoan(address payable receiver, uint256 amount, bytes calldata data) external override nonReentrant {
        if (amount == 0 || receiver == address(0)) {
            revert ZeroInput();
        }

        uint256 balanceBefore = IERC20(USDB).balanceOf(address(this));
        IERC20(USDB).safeTransfer(receiver, amount);
        IOutFlashCallee(receiver).execute(msg.sender, amount, data);

        uint256 providerFeeAmount;
        uint256 protocolFeeAmount;
        
        providerFeeAmount = amount * _flashLoanFee.providerFeeRate / RATIO;
        protocolFeeAmount = amount * _flashLoanFee.protocolFeeRate / RATIO;
        if (IERC20(USDB).balanceOf(address(this)) < balanceBefore + providerFeeAmount + protocolFeeAmount) {
            revert FlashLoanRepayFailed();
        }
        
        
        IRUSD(RUSD).mint(_RUSDStakeManager, providerFeeAmount);
        IERC20(USDB).safeTransfer(_revenuePool, protocolFeeAmount);
        emit FlashLoan(receiver, amount);
    }

    
    function setProtocolFee(uint256 protocolFee_) public override onlyOwner {
        if (protocolFee_ > RATIO) {
            revert FeeRateOverflow();
        }

        _protocolFee = protocolFee_;
        emit SetProtocolFee(protocolFee_);
    }

    function setFlashLoanFee(uint256 _providerFeeRate, uint256 _protocolFeeRate) public override onlyOwner {
        if (_providerFeeRate + _protocolFeeRate > RATIO) {
            revert FeeRateOverflow();
        }

        _flashLoanFee = FlashLoanFee(_providerFeeRate, _protocolFeeRate);
        emit SetFlashLoanFee(_providerFeeRate, _protocolFeeRate);
    }

    function setRevenuePool(address _pool) public override onlyOwner {
        _revenuePool = _pool;
        emit SetRevenuePool(_pool);
    }

    function setRUSDStakeManager(address _stakeManager) public override onlyOwner {
        _RUSDStakeManager = _stakeManager;
        emit SetRUSDStakeManager(_stakeManager);
    }
}