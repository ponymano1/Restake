// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IRETH.sol";
import "../../utils/Initializable.sol";
import "../../vault/interfaces/IOutETHVault.sol";

/**
 * @title ETH Wrapped Token. same as WETH
 */
contract RETH is IRETH, ERC20, Initializable, Ownable {
    address private _outETHVault;

    modifier onlyOutETHVault() {
        if (msg.sender != _outETHVault) {
            revert PermissionDenied();
        }
        _;
    }

    constructor(address owner) ERC20("RETH", "RETH") Ownable(owner) {}

    function outETHVault() external view override returns (address) {
        return _outETHVault;
    }

    /**
     * @dev Initializer
     * @param _vault - Address of OutETHVault
     */
    function initialize(address _vault) external override initializer {
        setOutETHVault(_vault);
    }

    /**
     * @dev deposit ETH and mint RETH
     */
    function deposit() public payable override {
        uint256 amount = msg.value;
        if (amount == 0) {
            revert ZeroInput();
        }

        address user = msg.sender;
        Address.sendValue(payable(_outETHVault), amount);
        _mint(user, amount);

        emit Deposit(user, amount);
    }

    /**
     * @dev withdraw ETH by RETH
     * @param amount - Amount of RETH for burn
     */
    function withdraw(uint256 amount) external override {
        if (amount == 0) {
            revert ZeroInput();
        }
        _burn(msg.sender, amount);
        IOutETHVault(_outETHVault).withdraw(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev OutETHVault fee
     */
    function mint(address _account, uint256 _amount) external override onlyOutETHVault {
        _mint(_account, _amount);
    }

    function setOutETHVault(address _vault) public override onlyOwner {
        _outETHVault = _vault;
        emit SetOutETHVault(_vault);
    }

    receive() external payable {
        deposit();
    }
}