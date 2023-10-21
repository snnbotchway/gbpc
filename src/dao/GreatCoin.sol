// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit, Nonces} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @custom:security-contact solomonbotchway7@gmail.com
contract GreatCoin is ERC20, ERC20Permit, ERC20Votes {
    constructor(address initialRecipient) ERC20("GreatCoin", "GRC") ERC20Permit("GreatCoin") {
        _mint(initialRecipient, 10_000_000_000 * 10 ** decimals());
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
