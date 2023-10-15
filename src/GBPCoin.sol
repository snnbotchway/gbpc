// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title GBPCoin - Great Britain Pound Coin
 * @author Solomon Botchway
 * @notice This contract represents the GBPCoin, which is designed to be pegged to the GBP (Great British Pound).
 * @dev GBPCoin is owned by the GBPVault contract, responsible for minting and burning GBPC as needed.
 * @custom:security-contact Contact: solomonbotchway7@gmail.com
 */
contract GBPCoin is ERC20, ERC20Burnable, Ownable {
    /**
     * @dev Constructs the GBPCoin contract with an initial owner. Ownership will be transferred to the vault after deployment.
     * @param initialOwner The initial owner of the contract.
     */
    constructor(address initialOwner) ERC20("GBP Coin", "GBPC") Ownable(initialOwner) {}

    /**
     * @dev Mints a specified amount of GBPC and assigns it to the recipient. Only the owner (vault) can call this function.
     * @param to The address to receive the minted GBPC.
     * @param amount The amount of GBPC to mint.
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns a specified amount of GBPC from the sender's account (The sender will always be the vault (onlyOwner)).
     * @param value The amount of GBPC to burn.
     */
    function burn(uint256 value) public override onlyOwner {
        super.burn(value);
    }

    /**
     * @dev Burns a specified amount of GBPC from a specified account. Only the owner (vault) can call this function.
     * @notice For the vault (owner) to burn GBPC from your account, you must approve the vault for the value to be burned.
     * @param account The account from which to burn GBPC.
     * @param value The amount of GBPC to burn.
     */
    function burnFrom(address account, uint256 value) public override onlyOwner {
        super.burnFrom(account, value);
    }
}
