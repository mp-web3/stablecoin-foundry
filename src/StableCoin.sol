// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Stable Coin
 * @author Mattia Papa
 * @dev Collateral: Exogenous (wBTC and wETH)
 * @dev Minting and Burning: Algorithmic
 * @dev Relative Stability: Pegged to USD
 * @dev This contract is meant to be governed by DSCEngine.
 * @dev This contract is just the ERC-20 implementation of the Decentralized Stable Coin Protocol.
 * @dev Ownable must be declared with an address of the contract owner
    as a parameter.
 */
contract StableCoin is ERC20Burnable, Ownable {
    error StableCoin_MustBeGreaterThanZero();
    error StableCoin_BurnAmountExceedsBalance();
    error StableCoin_CannotMintToZeroAddress();

    constructor()
        ERC20("StableCoin", "SC")
        Ownable(0x9c03Ce240E2D6EEB70B7Ebe73B1289EF4ecBF5A6)
    {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableCoin_MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert StableCoin_BurnAmountExceedsBalance();
        }
        // "super" keyword is used to access the burn function of the parent contract (ERC20Burnable)
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoin_CannotMintToZeroAddress();
        }
        if (_amount <= 0) {
            revert StableCoin_MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
