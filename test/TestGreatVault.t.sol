// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockV3Aggregator} from "chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {DeployGBPSystem} from "script/DeployGBPSystem.s.sol";
import {GBPCoin} from "src/GBPCoin.sol";
import {GreatDAO} from "src/dao/GreatDAO.sol";
import {GreatCoin} from "src/dao/GreatCoin.sol";
import {GreatTimeLock} from "src/dao/GreatTimeLock.sol";
import {GreatVault} from "src/GreatVault.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VaultMaster} from "src/VaultMaster.sol";
import {USDPriceFeed} from "src/utils/Structs.sol";

contract TestGreatVault is Test {
    using Math for uint256;

    GBPCoin public gbpCoin;
    GreatCoin public greatCoin;
    GreatDAO public greatDAO;
    GreatTimeLock public timelock;
    GreatVault public greatVault;
    VaultMaster public vaultMaster;
    HelperConfig public config;

    ERC20Mock public wEth;
    address public wEthUsdPriceFeed;
    uint8 public wEthUsdPriceFeedDecimals;
    address public gbpUsdPriceFeed;
    uint8 public gbpUsdPriceFeedDecimals;

    uint8 public constant LIQUIDATION_THRESHOLD = 80;
    uint8 public constant LIQUIDATION_SPREAD = 10;
    uint8 public constant CLOSE_FACTOR = 50;

    uint64 public constant MIN_HEALTH_FACTOR = 1e18;
    uint64 public constant PRECISION = 1e18;
    uint8 public constant ONE_HUNDRED_PERCENT = 100;

    uint256 public constant COLLATERAL_AMOUNT = 3e18;
    uint256 public ALOT = type(uint128).max;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    function setUp() public {
        DeployGBPSystem deployer = new DeployGBPSystem();
        (greatDAO, timelock, vaultMaster, gbpCoin, greatCoin, config) = deployer.run();

        address wEthAddress;
        (, gbpUsdPriceFeed, gbpUsdPriceFeedDecimals, wEthAddress, wEthUsdPriceFeed, wEthUsdPriceFeedDecimals) =
            config.activeNetworkConfig();

        vm.prank(address(timelock));
        vaultMaster.deployVault(
            wEthAddress, wEthUsdPriceFeed, wEthUsdPriceFeedDecimals, LIQUIDATION_THRESHOLD, LIQUIDATION_SPREAD, CLOSE_FACTOR
        );

        greatVault = GreatVault(vaultMaster.collateralVault(wEthAddress));

        wEth = ERC20Mock(wEthAddress);
        wEth.mint(USER, ALOT);
        wEth.mint(LIQUIDATOR, ALOT);

        vm.startPrank(USER);
        wEth.approve(address(greatVault), ALOT);
        gbpCoin.approve(address(greatVault), ALOT);
        vm.stopPrank();

        // Get LIQUIDATOR alot of GBPC for liquidations.
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(ALOT);
        vm.startPrank(LIQUIDATOR);
        wEth.approve(address(greatVault), ALOT);
        greatVault.depositCollateralAndMintGBPC(ALOT, maxMintableGbpc);
        gbpCoin.approve(address(greatVault), ALOT);
        vm.stopPrank();
    }

    /* ========================= DEPLOY ========================= */

    function testTimeLockIsTheOwner() public {
        assertEq(greatVault.owner(), address(timelock), "Timelock should be the owner");
    }

    function testSetsTheVaultMasterCorrectly() public {
        assertEq(greatVault.vaultMaster(), address(vaultMaster));
    }

    function testSetsTheCollateralCorrectly() public {
        assertEq(greatVault.collateral(), address(wEth));
    }

    function testSetsTheCollateralUsdPriceFeedCorrectly() public {
        USDPriceFeed memory priceFeed = greatVault.collateralUsdPriceFeed();

        assertEq(priceFeed.feed, wEthUsdPriceFeed);
        assertEq(priceFeed.decimals, wEthUsdPriceFeedDecimals);
    }

    function testSetsTheLiquidationThresholdCorrectly() public {
        assertEq(greatVault.liquidationThreshold(), LIQUIDATION_THRESHOLD);
    }

    function testSetsTheLiquidationSpreadCorrectly() public {
        assertEq(greatVault.liquidationSpread(), LIQUIDATION_SPREAD);
    }

    function testSetsTheCloseFactorCorrectly() public {
        assertEq(greatVault.closeFactor(), CLOSE_FACTOR);
    }

    /* ========================= DEPOSIT COLLATERAL AND MINT GBPC ========================= */

    function testRevertsIfHealthFactorWillBreak() public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);

        vm.expectRevert(GreatVault.GV__HealthFactorBroken.selector);
        vm.prank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc + 1);
    }

    function testDepositsCollateralForTheCaller() public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);
        uint256 initialVaultWethBal = wEth.balanceOf(address(greatVault));
        uint256 initialUserWethBal = wEth.balanceOf(address(USER));

        vm.prank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc);

        uint256 finalVaultWethBal = wEth.balanceOf(address(greatVault));
        uint256 finalUserWethBal = wEth.balanceOf(address(USER));
        assertEq(greatVault.collateralBalance(USER), COLLATERAL_AMOUNT);
        assertEq(finalVaultWethBal - initialVaultWethBal, COLLATERAL_AMOUNT);
        assertEq(initialUserWethBal - finalUserWethBal, COLLATERAL_AMOUNT);
    }

    function testMintsGbpcToTheCaller() public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);

        vm.prank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc);

        assertEq(gbpCoin.balanceOf(USER), maxMintableGbpc);
        assertEq(greatVault.gbpcMinted(USER), maxMintableGbpc);
    }

    /* ========================= BURN GBPC AND WITHDRAW COLLATERAL ========================= */

    function testItRevertsIfHealthFactorWillBreak() public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);

        vm.prank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc);

        // Withdrawing and burning these exact amounts should not revert.
        // Withdrawing any more or burning any less should revert.
        uint256 wEthToWithdraw = COLLATERAL_AMOUNT / 2;
        uint256 gbpcToBurn = (maxMintableGbpc / 2) + 1;

        vm.startPrank(USER);

        // Withdrawing more should revert.
        vm.expectRevert(GreatVault.GV__HealthFactorBroken.selector);
        greatVault.burnGBPCandWithdrawCollateral(gbpcToBurn, wEthToWithdraw + 1);

        // Burning less should revert.
        vm.expectRevert(GreatVault.GV__HealthFactorBroken.selector);
        greatVault.burnGBPCandWithdrawCollateral(gbpcToBurn - 1, wEthToWithdraw);

        // Should not revert
        greatVault.burnGBPCandWithdrawCollateral(gbpcToBurn, wEthToWithdraw);

        vm.stopPrank();
    }

    function testBurnsGbpcFromTheCaller() public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);

        vm.prank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc);

        uint256 wEthToWithdraw = COLLATERAL_AMOUNT / 2;
        uint256 gbpcToBurn = (maxMintableGbpc / 2) + 1;
        uint256 initialUserGbpcBal = gbpCoin.balanceOf(USER);
        uint256 initialUserGbpcMinted = greatVault.gbpcMinted(USER);

        vm.prank(USER);
        greatVault.burnGBPCandWithdrawCollateral(gbpcToBurn, wEthToWithdraw);

        uint256 finalUserGbpcBal = gbpCoin.balanceOf(USER);
        uint256 finalUserGbpcMinted = greatVault.gbpcMinted(USER);
        assertEq(initialUserGbpcBal - finalUserGbpcBal, gbpcToBurn);
        assertEq(initialUserGbpcMinted - finalUserGbpcMinted, gbpcToBurn);
    }

    function testWithdrawsCollateralToTheCaller() public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);

        vm.prank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc);

        uint256 wEthToWithdraw = COLLATERAL_AMOUNT / 2;
        uint256 gbpcToBurn = (maxMintableGbpc / 2) + 1;
        uint256 initialUserWethBal = wEth.balanceOf(USER);
        uint256 initialUserCollateralBal = greatVault.collateralBalance(USER);

        vm.prank(USER);
        greatVault.burnGBPCandWithdrawCollateral(gbpcToBurn, wEthToWithdraw);

        uint256 finalUserWethBal = wEth.balanceOf(USER);
        uint256 finalUserCollateralBal = greatVault.collateralBalance(USER);
        assertEq(finalUserWethBal - initialUserWethBal, wEthToWithdraw);
        assertEq(initialUserCollateralBal - finalUserCollateralBal, wEthToWithdraw);
    }

    /* ========================= WITHDRAW COLLATERAL ========================= */

    function testWillRevertIfHealthFactorBreaks() public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);

        vm.startPrank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc);

        // We borrowed the max, any further withdraw of collateral should break the health factor
        vm.expectRevert(GreatVault.GV__HealthFactorBroken.selector);
        greatVault.withdrawCollateral(1);
        vm.stopPrank();
    }

    function testItWithdrawsCollateralToTheCaller() public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);
        uint256 amountToBorrow = maxMintableGbpc / 2;
        uint256 wEthToWithdraw = COLLATERAL_AMOUNT / 2;

        vm.startPrank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, amountToBorrow);
        uint256 initialUserWethBal = wEth.balanceOf(USER);
        uint256 initialUserCollateralBal = greatVault.collateralBalance(USER);

        greatVault.withdrawCollateral(wEthToWithdraw);
        vm.stopPrank();

        uint256 finalUserWethBal = wEth.balanceOf(USER);
        uint256 finalUserCollateralBal = greatVault.collateralBalance(USER);
        assertEq(finalUserWethBal - initialUserWethBal, wEthToWithdraw);
        assertEq(initialUserCollateralBal - finalUserCollateralBal, wEthToWithdraw);
    }

    /* ========================= BURN GBPC ========================= */

    function testItBurnsGbpcFromTheCaller(uint256 gbpcToBurn) public {
        vm.assume(gbpcToBurn != 0);

        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);
        vm.assume(gbpcToBurn <= maxMintableGbpc);

        vm.startPrank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc);
        uint256 initialUserGbpcBal = gbpCoin.balanceOf(USER);
        uint256 initialUserGbpcMinted = greatVault.gbpcMinted(USER);

        greatVault.burnGBPC(gbpcToBurn);
        vm.stopPrank();

        uint256 finalUserGbpcBal = gbpCoin.balanceOf(USER);
        uint256 finalUserGbpcMinted = greatVault.gbpcMinted(USER);
        assertEq(initialUserGbpcBal - finalUserGbpcBal, gbpcToBurn);
        assertEq(initialUserGbpcMinted - finalUserGbpcMinted, gbpcToBurn);
    }

    /* ========================= LIQUIDATE ========================= */

    function testRevertsIfHealthFactorIsNotBroken(uint256 gbpcToMint) public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);
        vm.assume(gbpcToMint <= maxMintableGbpc);

        uint256 gbpcToRepay = gbpcToMint.mulDiv(CLOSE_FACTOR, ONE_HUNDRED_PERCENT);
        vm.assume(gbpcToRepay != 0);

        vm.prank(USER);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, gbpcToMint);

        uint256 healthFactor = greatVault.healthFactor(USER);
        assert(healthFactor >= MIN_HEALTH_FACTOR);

        vm.expectRevert(abi.encodeWithSelector(GreatVault.GV__HealthFactorNotBroken.selector, healthFactor));
        vm.prank(LIQUIDATOR);
        greatVault.liquidate(USER, gbpcToRepay);
    }

    function _breakHealthFactorOf(address account) internal returns (uint256 closeFactorAmount) {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(COLLATERAL_AMOUNT);

        vm.prank(account);
        greatVault.depositCollateralAndMintGBPC(COLLATERAL_AMOUNT, maxMintableGbpc);

        (, int256 wethUsdPrice,,,) = AggregatorV3Interface(wEthUsdPriceFeed).latestRoundData();

        // Reduce the price of wEth while the health factor is exactly 1.
        MockV3Aggregator(wEthUsdPriceFeed).updateAnswer(wethUsdPrice - 1);
        assert(greatVault.healthFactor(account) < MIN_HEALTH_FACTOR);

        closeFactorAmount = maxMintableGbpc.mulDiv(CLOSE_FACTOR, ONE_HUNDRED_PERCENT);
    }

    function testRevertsIfRepayAmountExceedsCloseFactor() public {
        uint256 closeFactorAmount = _breakHealthFactorOf(USER);
        uint256 gbpcToRepay = closeFactorAmount + 1;

        vm.expectRevert(abi.encodeWithSelector(GreatVault.GV__CloseFactorAmountExceeded.selector, closeFactorAmount));
        vm.prank(LIQUIDATOR);
        greatVault.liquidate(USER, gbpcToRepay);
    }

    function testGbpcIsBurntFromLiquidatorToCoverSomeDebt(uint256 gbpcToRepay) public {
        // Very small GBPC amounts which are inferior to WETH will not have any effect on the health factor
        vm.assume(gbpcToRepay > 1e4);

        uint256 closeFactorAmount = _breakHealthFactorOf(USER);
        vm.assume(gbpcToRepay <= closeFactorAmount);

        uint256 initialLiquidatorGbpcBal = gbpCoin.balanceOf(LIQUIDATOR);
        uint256 initialUserGbpcMinted = greatVault.gbpcMinted(USER);

        vm.prank(LIQUIDATOR);
        greatVault.liquidate(USER, gbpcToRepay);

        uint256 finalLiquidatorGbpcBal = gbpCoin.balanceOf(LIQUIDATOR);
        uint256 finalUserGbpcMinted = greatVault.gbpcMinted(USER);
        assertEq(initialLiquidatorGbpcBal - finalLiquidatorGbpcBal, gbpcToRepay);
        assertEq(initialUserGbpcMinted - finalUserGbpcMinted, gbpcToRepay);
    }

    function testLiquidatorReceivesSomeCollateralAtADiscount(uint256 gbpcToRepay) public {
        // Very small GBPC amounts which are inferior to WETH will not have any effect on the health factor
        vm.assume(gbpcToRepay > 1e4);

        uint256 closeFactorAmount = _breakHealthFactorOf(USER);
        vm.assume(gbpcToRepay <= closeFactorAmount);

        uint256 initialLiquidatorWethBal = wEth.balanceOf(LIQUIDATOR);
        uint256 initialUserCollateralBal = greatVault.collateralBalance(USER);
        uint256 expectedLiquidatorCollateral = greatVault.previewLiquidate(gbpcToRepay);

        vm.prank(LIQUIDATOR);
        greatVault.liquidate(USER, gbpcToRepay);

        uint256 finalLiquidatorWethBal = wEth.balanceOf(LIQUIDATOR);
        uint256 finalUserCollateralBal = greatVault.collateralBalance(USER);
        assertEq(finalLiquidatorWethBal - initialLiquidatorWethBal, expectedLiquidatorCollateral);
        assertEq(initialUserCollateralBal - finalUserCollateralBal, expectedLiquidatorCollateral);
    }

    /* ========================= PREVIEW LIQUIDATE ========================= */

    function testReturnsTheCorrectLiquatorCollateralAmount() public {
        uint256 gbpcToRepay = 4200 * 10 ** gbpCoin.decimals();

        // For a 10% liquidation spread, paying GBP 4200.00 will earn you GBP 4620.00 worth of collateral
        uint256 expectedCollateralAmount = greatVault.gbpToCollateral(4620 * 10 ** gbpCoin.decimals());

        uint256 collateralAmount = greatVault.previewLiquidate(gbpcToRepay);

        assertEq(collateralAmount, expectedCollateralAmount);
    }

    /* ========================= PREVIEW DEPOSIT COLLATERAL ========================= */

    function testReturnsMaxGbpcYouCanMintForSpecifiedCollateral(uint128 collateralAmount) public {
        vm.assume(collateralAmount > 1);
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(collateralAmount);

        vm.startPrank(USER);

        // Should break health factor if collateral is less than the minimum.
        vm.expectRevert(GreatVault.GV__HealthFactorBroken.selector);
        greatVault.depositCollateralAndMintGBPC(collateralAmount - 1, maxMintableGbpc);

        // Should break health factor if GBPC minted is more than the maximum.
        vm.expectRevert(GreatVault.GV__HealthFactorBroken.selector);
        greatVault.depositCollateralAndMintGBPC(collateralAmount, maxMintableGbpc + 1);

        // Should not break health factor
        greatVault.depositCollateralAndMintGBPC(collateralAmount, maxMintableGbpc);

        vm.stopPrank();
    }

    /* ========================= PREVIEW MINT GBPC ========================= */

    function testReturnsMinCollateralToDepositForSpecifiedGbpcToMint(uint128 collateralAmount) public {
        uint256 maxMintableGbpc = greatVault.previewDepositCollateral(collateralAmount);
        uint256 minCollateralDeposit = greatVault.previewMintGBPC(maxMintableGbpc);

        assertEq(minCollateralDeposit, collateralAmount);
    }

    /* =========================  COLLATERAL AND GBPC PRICE CONVERSIONS ========================= */

    function testCollateralToGbp() public {
        uint256 ethGbpAmount = greatVault.collateralToGbp(COLLATERAL_AMOUNT);
        uint256 expectedgbpAmount = 3968015794669299111549; // Pre-calculated with mock price feed data

        assertEq(ethGbpAmount, expectedgbpAmount);
    }

    function testgbpToCollateral() public {
        uint256 gbpEthAmount = greatVault.gbpToCollateral(3968015794669299111550);
        uint256 expectedEthAmount = COLLATERAL_AMOUNT; // Pre-calculated with mock price feed data

        assertEq(gbpEthAmount, expectedEthAmount);
    }
}
