// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {DeployGBPSystem} from "script/DeployGBPSystem.s.sol";
import {GBPCoin} from "src/GBPCoin.sol";
import {GreatDAO} from "src/dao/GreatDAO.sol";
import {GreatCoin} from "src/dao/GreatCoin.sol";
import {GreatTimeLock} from "src/dao/GreatTimeLock.sol";
import {GreatVault} from "src/GreatVault.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VaultMaster} from "src/VaultMaster.sol";

contract TestGBPCoin is Test {
    GBPCoin public gbpCoin;
    GreatCoin public greatCoin;
    GreatDAO public greatDAO;
    GreatTimeLock public timelock;
    GreatVault public greatVault;
    VaultMaster public vaultMaster;
    HelperConfig public config;
    DeployGBPSystem public deployer;

    uint8 public constant LIQUIDATION_THRESHOLD = 80;
    uint8 public constant LIQUIDATION_SPREAD = 10;
    uint8 public constant CLOSE_FACTOR = 50;

    function setUp() public {
        deployer = new DeployGBPSystem();
        (greatDAO, timelock, vaultMaster, gbpCoin, greatCoin, config) = deployer.run();

        (,,, address wEth, address wEthUsdPriceFeed, uint8 wEthUsdPriceFeedDecimals) = config.activeNetworkConfig();

        vm.prank(address(timelock));
        vaultMaster.deployVault(
            wEth, wEthUsdPriceFeed, wEthUsdPriceFeedDecimals, LIQUIDATION_THRESHOLD, LIQUIDATION_SPREAD, CLOSE_FACTOR
        );

        greatVault = GreatVault(vaultMaster.collateralVault(wEth));
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

        vm.prank(address(greatVault));
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

        address vault = address(greatVault);

        vm.prank(vault);
        gbpCoin.mint(vault, prevBal);

        vm.prank(vault);
        gbpCoin.burn(amount);

        assertEq(gbpCoin.balanceOf(vault), prevBal - amount);
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

        address vault = address(greatVault);

        vm.prank(vault);
        gbpCoin.mint(from, prevBal);

        vm.prank(from);
        gbpCoin.approve(vault, amount);

        vm.prank(vault);
        gbpCoin.burnFrom(from, amount);

        assertEq(gbpCoin.balanceOf(from), prevBal - amount);
    }
}
