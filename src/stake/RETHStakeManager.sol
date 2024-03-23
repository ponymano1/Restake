//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../utils/Initializable.sol";
import "../utils/AutoIncrementId.sol";
import "../token/ETH/interfaces/IREY.sol";
import "../token/ETH/interfaces/IRETH.sol";
import "../token/ETH/interfaces/IPETH.sol";
import "../vault/interfaces/IOutETHVault.sol";
import "./interfaces/IRETHStakeManager.sol";

/**
 * @title RETH Stake Manager Contract
 * @dev Handles Staking of RETH
 */
contract RETHStakeManager is IRETHStakeManager, Initializable, Ownable, AutoIncrementId {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    uint256 public constant RATIO = 10000;
    uint256 public constant MINSTAKE = 1e16;
    uint256 public constant DAY = 24 * 3600;

    address public immutable RETH;
    address public immutable PETH;
    address public immutable REY;

    address private _outETHVault;
    uint256 private _forceUnstakeFee;
    uint16 private _minLockupDays;
    uint16 private _maxLockupDays;
    uint256 private _totalStaked;
    uint256 private _totalYieldPool;

    mapping(uint256 positionId => Position) private _positions;

    modifier onlyOutETHVault() {
        if (msg.sender != _outETHVault) {
            revert PermissionDenied();
        }
        _;
    }

    /**
     * @param owner - Address of the owner
     * @param reth - Address of RETH Token
     * @param peth - Address of PETH Token
     * @param rey - Address of REY Token
     */
    constructor(address owner, address reth, address peth, address rey) Ownable(owner) {
        RETH = reth;
        PETH = peth;
        REY = rey;
    }

    /** view **/
    function outETHVault() external view override returns (address) {
        return _outETHVault;
    }

    function forceUnstakeFee() external view override returns (uint256) {
        return _forceUnstakeFee;
    }

    function totalStaked() external view override returns (uint256) {
        return _totalStaked;
    }

    function totalYieldPool() external view override returns (uint256) {
        return _totalYieldPool;
    }

    function minLockupDays() external view override returns (uint16) {
        return _minLockupDays;
    }

    function maxLockupDays() external view override returns (uint16) {
        return _maxLockupDays;
    }

    function positionsOf(uint256 positionId) external view override returns (Position memory) {
        return _positions[positionId];
    }

    function getStakedRETH() public view override returns (uint256) {
        return IRETH(RETH).balanceOf(address(this));
    }

    function avgStakeDays() public view override returns (uint256) {
        return IERC20(REY).totalSupply() / _totalStaked;
    }
    
    /**
     *@dev Calculate PETH amount
     * amountOfPETH = amountInRETH * totalshare(PETH TotalSupply) / totalAsset(RETH TotalSupply)
     */
    function calcPETHAmount(uint256 amountInRETH) public view override returns (uint256) {
        uint256 totalShares = IRETH(PETH).totalSupply();
        totalShares = totalShares == 0 ? 1 : totalShares;

        uint256 yieldVault = getStakedRETH();
        yieldVault = yieldVault == 0 ? 1 : yieldVault;

        return amountInRETH * totalShares / yieldVault;
        
    }

    /** function **/
    /**
     * @dev Initializer
     * @param outETHVault_ - Address of OutETHVault
     * @param forceUnstakeFee_ - Force unstake fee
     * @param minLockupDays_ - Min lockup days
     * @param maxLockupDays_ - Max lockup days
     */
    function initialize(
        address outETHVault_,
        uint256 forceUnstakeFee_, 
        uint16 minLockupDays_, 
        uint16 maxLockupDays_
    ) external override initializer {
        setOutETHVault(outETHVault_);
        setForceUnstakeFee(forceUnstakeFee_);
        setMinLockupDays(minLockupDays_);
        setMaxLockupDays(maxLockupDays_);
    }

    /**
     * @dev Stake RETH, then mints PETH and REY for the user.
     * New mint amountOfPETH = amountInRETH * totalshare(PETH TotalSupply) / totalAsset(RETH TotalSupply)
     * New mint REY = amountInRETH * lockupDays
     * @param amountInRETH - RETH staked amount, amount % 1e15 == 0
     * @param lockupDays - User can withdraw after lockupDays
     * @param positionOwner - Owner of position
     * @param pethTo - Receiver of PETH
     * @param reyTo - Receiver of REY
     * @notice User must have approved this contract to spend RETH
     */
    function stake(uint256 amountInRETH, uint16 lockupDays, address positionOwner, address pethTo, address reyTo)
        external
        override
        returns (uint256, uint256)
    {
        if (amountInRETH < MINSTAKE) {
            revert MinStakeInsufficient(MINSTAKE);
        }
        if (lockupDays < _minLockupDays || lockupDays > _maxLockupDays) {
            revert InvalidLockupDays(_minLockupDays, _maxLockupDays);
        }

        address msgSender = msg.sender;
        uint256 amountInPETH = calcPETHAmount(amountInRETH);
        uint256 positionId = nextId();
        uint256 deadline;
        uint256 amountInREY;
        
        _totalStaked += amountInRETH;
        deadline = block.timestamp + lockupDays * DAY;
        amountInREY = amountInRETH * lockupDays;
        
        _positions[positionId] = Position
        (
            amountInRETH.toUint96(), 
            amountInPETH.toUint96(), 
            deadline.toUint56(), 
            false, 
            positionOwner
        );

        IERC20(RETH).safeTransferFrom(msgSender, address(this), amountInRETH);
        IPETH(PETH).mint(pethTo, amountInPETH);
        IREY(REY).mint(reyTo, amountInREY);

        emit StakeRETH(positionId, positionOwner, amountInRETH, deadline);
        return (amountInPETH, amountInREY);
    }

    /**
     * @dev Allows user to unstake funds. not allowed force unstake.
     * forbid user to unstake before deadline
     * @param positionId - Staked Principal Position Id
     */
    function unstake(uint256 positionId) external returns (uint256) {
        address msgSender = msg.sender;
        Position storage position = _positions[positionId];
        if (position.closed) {
            revert PositionClosed();
        }
        if (position.owner != msgSender) {
            revert PermissionDenied();
        }

        if (position.deadline > block.timestamp) {
            revert NotReachedDeadline(position.deadline);
        }

        position.closed = true;
        uint256 amountInRETH = position.RETHAmount;
        _totalStaked -= amountInRETH;
        
        IPETH(PETH).burn(msgSender, position.PETHAmount);

        // uint256 deadline = position.deadline;
        // uint256 currentTime = block.timestamp;
      
        IERC20(RETH).safeTransfer(msgSender, amountInRETH);

        emit Unstake(positionId, msgSender, amountInRETH);
        return amountInRETH;
    }

    /**
     * @dev extend lock time and mint new REY for the extension
     * 
     * @param positionId - Staked Principal Position Id
     * @param extendDays - Extend lockup days
     */
    function extendLockTime(uint256 positionId, uint256 extendDays) external returns (uint256) {
        address user = msg.sender;
        Position memory position = _positions[positionId];
        if (position.owner != user) {
            revert PermissionDenied();
        }
        uint256 currentTime = block.timestamp;
        uint256 deadline = position.deadline;
        if (deadline <= currentTime) {
            revert ReachedDeadline(deadline);
        }
        uint256 newDeadLine = deadline + extendDays * DAY;
        uint256 intervalDaysFromNow = (newDeadLine - currentTime) / DAY;
        if (intervalDaysFromNow < _minLockupDays || intervalDaysFromNow > _maxLockupDays) {
            revert InvalidExtendDays();
        }
        position.deadline = newDeadLine.toUint56();

        uint256 amountInREY;
        //mint new REY for the extension
        amountInREY = position.RETHAmount * extendDays;
        
        IREY(REY).mint(user, amountInREY);

        emit ExtendLockTime(positionId, extendDays, amountInREY);
        return amountInREY;
    }

    /**
     * @dev burn REY to  withdraw yield, send RETH to user
     * RETH amount = amountInREY * totalYieldPool(RETH) / totalSupply(REY)
     * @param amountInREY - Amount of REY
     */
    function withdrawYield(uint256 amountInREY) external override returns (uint256) {
        if (amountInREY == 0) {
            revert ZeroInput();
        }
        
        //call Vault claimETHYield to claim all yield
        IOutETHVault(_outETHVault).claimETHYield();
        uint256 yieldAmount;
        yieldAmount = amountInREY * _totalYieldPool  / IREY(REY).totalSupply();
        

        address user = msg.sender;
        IREY(REY).burn(user, amountInREY);
        IERC20(RETH).safeTransfer(user, yieldAmount);

        emit WithdrawYield(user, amountInREY, yieldAmount);
        return yieldAmount;
    }

    /**
     * @param nativeYield - Additional native yield amount
     */
    function updateYieldPool(uint256 nativeYield) external override onlyOutETHVault {
        _totalYieldPool += nativeYield;
    }

    /** setter **/
    /**
     * @param minLockupDays_ - Min lockup days
     */
    function setMinLockupDays(uint16 minLockupDays_) public onlyOwner {
        _minLockupDays = minLockupDays_;
        emit SetMinLockupDays(minLockupDays_);
    }

    /**
     * @param maxLockupDays_ - Max lockup days
     */
    function setMaxLockupDays(uint16 maxLockupDays_) public onlyOwner {
        _maxLockupDays = maxLockupDays_;
        emit SetMaxLockupDays(maxLockupDays_);
    }

    /**
     * @param forceUnstakeFee_ - Force unstake fee, 
     * @notice not used in this version, not allow ForceUnstake
     */
    function setForceUnstakeFee(uint256 forceUnstakeFee_) public override onlyOwner {
        if (forceUnstakeFee_ > RATIO) {
            revert ForceUnstakeFeeOverflow();
        }

        _forceUnstakeFee = forceUnstakeFee_;
        emit SetForceUnstakeFee(forceUnstakeFee_);
    }

    /**
     * @param outETHVault_ - Address of outETHVault
     */
    function setOutETHVault(address outETHVault_) public override onlyOwner {
        _outETHVault = outETHVault_;
        emit SetOutETHVault(outETHVault_);
    }

    receive() external payable {
        revert();
    }
}
