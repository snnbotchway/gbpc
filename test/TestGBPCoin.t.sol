// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {DeployGBPSystem} from "script/DeployGBPSystem.s.sol";
import {GBPCoin} from "src/GBPCoin.sol";
import {VaultMaster} from "src/VaultMaster.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract TestGBPCoin is Test {
    DeployGBPSystem deployer;
    GBPCoin gbpCoin;
    VaultMaster vaultMaster;

    function setUp() public {
        deployer = new DeployGBPSystem();
        (gbpCoin, vaultMaster) = deployer.run();
    }

    /* ========================= DEPLOY ========================= */

    function testVaultMasterIsAdmin() public view {
        bytes32 adminRole = gbpCoin.DEFAULT_ADMIN_ROLE();

        assert(gbpCoin.hasRole(adminRole, address(vaultMaster)));
    }

    function testTokenNameIsGBPCoin() public {
        assertEq(gbpCoin.name(), "GBP Coin");
    }

    function testTokenSymbolIsGBPC() public {
        assertEq(gbpCoin.symbol(), "GBPC");
    }

    /* ========================= MINT ========================= */

    function testOnlyMinterCanMint(address caller, address to, uint256 amount) public {
        bytes32 minterRole = gbpCoin.MINTER_ROLE();
        vm.assume(!gbpCoin.hasRole(minterRole, caller));

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, minterRole));
        vm.prank(caller);
        gbpCoin.mint(to, amount);
    }

    function testMintsAmountToSpecifiedAddress(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount != 0);

        vm.prank(address(vaultMaster));
        gbpCoin.mint(to, amount);

        assertEq(gbpCoin.balanceOf(to), amount);
    }

    /* ========================= BURN ========================= */

    function testOnlyMinterCanBurn(address caller, uint256 amount) public {
        bytes32 minterRole = gbpCoin.MINTER_ROLE();
        vm.assume(!gbpCoin.hasRole(minterRole, caller));

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, minterRole));
        vm.prank(caller);
        gbpCoin.burn(amount);
    }

    function testBurnsAmountFromSendersAccount(uint256 prevBal, uint256 amount) public {
        vm.assume(prevBal >= amount);
        vm.assume(amount != 0);

        vm.prank(address(vaultMaster));
        gbpCoin.mint(address(vaultMaster), prevBal);

        vm.prank(address(vaultMaster));
        gbpCoin.burn(amount);

        assertEq(gbpCoin.balanceOf(address(vaultMaster)), prevBal - amount);
    }

    /* ========================= BURN FROM ========================= */

    function testOnlyMinterCanBurnFrom(address caller, address from, uint256 amount) public {
        bytes32 minterRole = gbpCoin.MINTER_ROLE();
        vm.assume(!gbpCoin.hasRole(minterRole, caller));

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, minterRole));
        vm.prank(caller);
        gbpCoin.burnFrom(from, amount);
    }

    function testBurnsAmountFromSpecifiedAccount(address from, uint256 prevBal, uint256 amount) public {
        vm.assume(prevBal >= amount);
        vm.assume(amount != 0);
        vm.assume(from != address(0));

        vm.prank(address(vaultMaster));
        gbpCoin.mint(from, prevBal);

        vm.prank(from);
        gbpCoin.approve(address(vaultMaster), amount);

        vm.prank(address(vaultMaster));
        gbpCoin.burnFrom(from, amount);

        assertEq(gbpCoin.balanceOf(from), prevBal - amount);
    }
}
