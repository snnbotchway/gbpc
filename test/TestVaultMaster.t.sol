// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DeployGBPSystem} from "script/DeployGBPSystem.s.sol";
import {GBPCoin} from "src/GBPCoin.sol";
import {GreatDAO} from "src/dao/GreatDAO.sol";
import {GreatCoin} from "src/dao/GreatCoin.sol";
import {GreatTimeLock} from "src/dao/GreatTimeLock.sol";
import {GreatVault} from "src/GreatVault.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VaultMaster} from "src/VaultMaster.sol";
import {USDPriceFeed} from "src/utils/Structs.sol";

contract TestVaultMaster is Test {
    GBPCoin public gbpCoin;
    GreatCoin public greatCoin;
    GreatDAO public greatDAO;
    GreatTimeLock public timelock;
    VaultMaster public vaultMaster;
    HelperConfig public config;
    DeployGBPSystem public deployer;

    address public wEth;
    address public wEthUsdPriceFeed;
    uint8 public wEthUsdPriceFeedDecimals;
    address public gbpUsdPriceFeed;
    uint8 public gbpUsdPriceFeedDecimals;

    uint8 public constant LIQUIDATION_THRESHOLD = 80;
    uint8 public constant LIQUIDATION_SPREAD = 10;
    uint8 public constant CLOSE_FACTOR = 50;

    function setUp() public {
        deployer = new DeployGBPSystem();
        (greatDAO, timelock, vaultMaster, gbpCoin, greatCoin, config) = deployer.run();

        (, gbpUsdPriceFeed, gbpUsdPriceFeedDecimals, wEth, wEthUsdPriceFeed, wEthUsdPriceFeedDecimals) =
            config.activeNetworkConfig();
    }

    /* ========================= DEPLOY ========================= */

    function testSetsTheGbpCoinCorrectly() public {
        assertEq(vaultMaster.gbpCoin(), address(gbpCoin));
    }

    function testSetsTheGbpUsdPriceFeedCorrectly() public {
        USDPriceFeed memory priceFeed = vaultMaster.gbpUsdPriceFeed();

        assertEq(priceFeed.feed, gbpUsdPriceFeed);
        assertEq(priceFeed.decimals, gbpUsdPriceFeedDecimals);
    }

    /* ========================= DEPLOY VAULT ========================= */

    function testRevertsIfCallerIsNotTheDAOsTimelock(address caller) public {
        vm.assume(caller != address(timelock));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        vaultMaster.deployVault(
            wEth, wEthUsdPriceFeed, wEthUsdPriceFeedDecimals, LIQUIDATION_THRESHOLD, LIQUIDATION_SPREAD, CLOSE_FACTOR
        );
    }

    function testAssignsCollateralToVaultMapping() public {
        vm.prank(address(timelock));
        vaultMaster.deployVault(
            wEth, wEthUsdPriceFeed, wEthUsdPriceFeedDecimals, LIQUIDATION_THRESHOLD, LIQUIDATION_SPREAD, CLOSE_FACTOR
        );

        GreatVault greatVault = GreatVault(vaultMaster.collateralVault(wEth));
        assertNotEq(address(greatVault), address(0));
    }

    function testGrantsTheGbpcMinterRoleToTheVault() public {
        vm.prank(address(timelock));
        vaultMaster.deployVault(
            wEth, wEthUsdPriceFeed, wEthUsdPriceFeedDecimals, LIQUIDATION_THRESHOLD, LIQUIDATION_SPREAD, CLOSE_FACTOR
        );

        GreatVault greatVault = GreatVault(vaultMaster.collateralVault(wEth));
        bytes32 minterRole = gbpCoin.MINTER_ROLE();
        assertTrue(gbpCoin.hasRole(minterRole, address(greatVault)));
    }
}
