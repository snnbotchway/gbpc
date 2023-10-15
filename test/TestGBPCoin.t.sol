// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {DeployGBPSystem} from "script/DeployGBPSystem.s.sol";
import {GBPCoin} from "src/GBPCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract TestGBPCoin is Test {
    DeployGBPSystem deployer;
    GBPCoin gbpCoin;

    function setUp() public {
        deployer = new DeployGBPSystem();
        gbpCoin = deployer.run();
    }

    /* ========================= DEPLOY ========================= */

    function testVaultIsOwner() public {
        // TODO: test vault is owner
        // assertEq (gbpCoin.owner(), address(greatVault));
    }

    function testTokenNameIsGBPCoin() public {
        assertEq(gbpCoin.name(), "GBP Coin");
    }

    function testTokenSymbolIsGBPC() public {
        assertEq(gbpCoin.symbol(), "GBPC");
    }

    /* ========================= MINT ========================= */

    function testOnlyOwnerCanMint(address caller, address to, uint256 amount) public {
        vm.assume(caller != gbpCoin.owner());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        gbpCoin.mint(to, amount);
    }

    function testMintsAmountToSpecifiedAddress(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount != 0);

        vm.prank(gbpCoin.owner());
        gbpCoin.mint(to, amount);

        assertEq(gbpCoin.balanceOf(to), amount);
    }

    /* ========================= BURN ========================= */

    function testOnlyOwnerCanBurn(address caller, uint256 amount) public {
        vm.assume(caller != gbpCoin.owner());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        gbpCoin.burn(amount);
    }

    function testBurnsAmountFromSendersAccount(uint256 prevBal, uint256 amount) public {
        vm.assume(prevBal >= amount);
        vm.assume(amount != 0);

        address owner = gbpCoin.owner();
        gbpCoin.mint(owner, prevBal);

        vm.prank(owner);
        gbpCoin.burn(amount);

        assertEq(gbpCoin.balanceOf(owner), prevBal - amount);
    }

    /* ========================= BURN FROM ========================= */

    function testOnlyOwnerCanBurnFrom(address caller, address from, uint256 amount) public {
        vm.assume(caller != gbpCoin.owner());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        gbpCoin.burnFrom(from, amount);
    }

    function testBurnsAmountFromSpecifiedAccount(address from, uint256 prevBal, uint256 amount) public {
        vm.assume(prevBal >= amount);
        vm.assume(amount != 0);
        vm.assume(from != address(0));

        gbpCoin.mint(from, prevBal);
        address owner = gbpCoin.owner();

        vm.prank(from);
        gbpCoin.approve(owner, amount);

        vm.prank(owner);
        gbpCoin.burnFrom(from, amount);

        assertEq(gbpCoin.balanceOf(from), prevBal - amount);
    }
}
