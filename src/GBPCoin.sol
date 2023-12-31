// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title GBPCoin - Great British Pound Coin
 * @author Solomon Botchway
 * @notice This contract represents the GBPCoin, which is designed to be pegged to the GBP (Great British Pound).
 * @dev The Vault Master is the Admin of this coin, and will deploy Vaults, giving them the MINTER_ROLE of this Coin.
 * The vaults are responsible for minting and burning GBPC as needed.
 * @custom:security-contact Contact: solomonbotchway7@gmail.com
 */
contract GBPCoin is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address defaultAdmin) ERC20("GBP Coin", "GBPC") {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /**
     * @dev Mints a specified amount of GBPC and assigns it to the recipient. Only the minters(Great Vaults) can call this function.
     * @param to The address to receive the minted GBPC.
     * @param amount The amount of GBPC to mint.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Burns a specified amount of GBPC from the sender's account. Only the minters(Great Vaults) can call this function.
     * @param value The amount of GBPC to burn.
     */
    function burn(uint256 value) public override onlyRole(MINTER_ROLE) {
        super.burn(value);
    }

    /**
     * @dev Burns a specified amount of GBPC from a specified account. Only the minters(Great Vaults) can call this function.
     * @notice For a Great Vault (minter) to burn GBPC from your account, you must approve the vault for the value to be burned.
     * @param account The account from which to burn GBPC.
     * @param value The amount of GBPC to burn.
     */
    function burnFrom(address account, uint256 value) public override onlyRole(MINTER_ROLE) {
        super.burnFrom(account, value);
    }
}
