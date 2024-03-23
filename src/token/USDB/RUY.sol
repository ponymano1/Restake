// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IRUY.sol";
import "../../utils/Initializable.sol";

/**
 * @title USD yield token
 */
contract RUY is IRUY, ERC20, Initializable, Ownable {
    address private _RUSDStakeManager;

    modifier onlyRUSDStakeManager() {
        if (msg.sender != _RUSDStakeManager) {
            revert PermissionDenied();
        }
        _;
    }

    constructor(address owner) ERC20("Outrun USD yield token", "RUY") Ownable(owner) {}

    function RUSDStakeManager() external view override returns (address) {
        return _RUSDStakeManager;
    }

    /**
     * @dev Initializer
     * @param stakeManager_ - Address of RUSDStakeManager
     */
    function initialize(address stakeManager_) external override initializer {
        setRUSDStakeManager(stakeManager_);
    }

    /**
     *  mint when the user stake RUSD
     * @param _account Address who stake RUSD 
     * @param _amount The amount of minted RUY
     */
    function mint(address _account, uint256 _amount) external override onlyRUSDStakeManager {
        _mint(_account, _amount);
    }

    /**
     * burn when the user redempt the native yield
     * @param _account Address who redempt the native yield
     * @param _amount The amount of burned RUY
     */
    function burn(address _account, uint256 _amount) external override onlyRUSDStakeManager {
        _burn(_account, _amount);
    }

    function setRUSDStakeManager(address _stakeManager) public override onlyOwner {
        _RUSDStakeManager = _stakeManager;
        emit SetRUSDStakeManager(_stakeManager);
    }
}