// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockV3Aggregator} from "chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {GBPCoin} from "src/GBPCoin.sol";
import {GreatVault} from "src/GreatVault.sol";
import {VaultMaster} from "src/VaultMaster.sol";
import {USDPriceFeed} from "src/utils/Structs.sol";
import {OracleLib} from "src/utils/OracleLib.sol";

contract SafetyCollateral is ERC20 {
    uint8 private immutable _decimals;
    uint8 public tax;
    bool public chargeExtra;
    address private _nestedDepositVault;
    uint256 private _nestedDepositAmount;

    constructor(uint8 decimals_) ERC20("Safety collateral", "COL") {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTax(uint8 tax_) external {
        tax = tax_;
    }

    function setChargeExtra(bool extra) external {
        chargeExtra = extra;
    }

    function prepareNestedDeposit(address vault, uint256 amount) external {
        _mint(address(this), amount);
        _approve(address(this), vault, amount);
        _nestedDepositVault = vault;
        _nestedDepositAmount = amount;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (_nestedDepositVault != address(0) && from != address(0)) {
            address nestedVault = _nestedDepositVault;
            _nestedDepositVault = address(0);
            try GreatVault(nestedVault).depositCollateral(_nestedDepositAmount) {} catch {}
        }
        uint256 fee = from != address(0) && to != address(0) ? amount * tax / 100 : 0;
        if (fee != 0) super._update(from, address(0), fee);
        super._update(from, to, chargeExtra ? amount : amount - fee);
    }
}

contract TestVaultSafety is Test {
    GBPCoin private coin;
    VaultMaster private master;
    SafetyCollateral private collateral;
    MockV3Aggregator private collateralFeed;
    MockV3Aggregator private gbpFeed;
    GreatVault private vault;
    address private borrower = address(0xb0);
    address private liquidator = address(0x11);

    function setUp() public {
        coin = new GBPCoin(address(this));
        gbpFeed = new MockV3Aggregator(8, 1e8);
        master = new VaultMaster(address(this), address(coin), address(gbpFeed), 8, 1 days);
        coin.grantRole(coin.DEFAULT_ADMIN_ROLE(), address(master));
        collateral = new SafetyCollateral(18);
        collateralFeed = new MockV3Aggregator(8, 125e8);
        master.deployVault(address(collateral), address(collateralFeed), 8, 1 days, 80, 10, 50);
        vault = GreatVault(master.collateralVault(address(collateral)));
        collateral.mint(borrower, 1e18);
        collateral.mint(liquidator, 2e18);
        vm.startPrank(liquidator);
        collateral.approve(address(vault), 2e18);
        vault.depositCollateralAndMintGBPC(2e18, 100e18);
        coin.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.prank(borrower);
        collateral.approve(address(vault), 1e18);
    }

    function testLiquidationCapsBonusAndRepaysSolventPosition() public {
        vm.prank(borrower);
        vault.depositCollateralAndMintGBPC(1e18, 100e18);
        collateralFeed.updateAnswer(105e8);
        assertEq(vault.healthFactor(borrower), 0.84e18);

        vm.prank(liquidator);
        vault.liquidate(borrower, 50e18);
        assertEq(vault.gbpcMinted(borrower), 50e18);
        assertEq(vault.collateralBalance(borrower), 0.5e18);
        assertEq(collateral.balanceOf(liquidator), 0.5e18);
        assertEq(vault.healthFactor(borrower), 0.84e18);

        vm.prank(liquidator);
        vault.liquidate(borrower, 50e18);
        assertEq(vault.gbpcMinted(borrower), 0);
        assertEq(vault.collateralBalance(borrower), 0);
        assertEq(collateral.balanceOf(liquidator), 1e18);
        assertEq(vault.badDebt(), 0);
    }

    function testExhaustedCollateralRecordsDebtAndAllowsVoluntaryCoverage() public {
        vm.prank(borrower);
        vault.depositCollateralAndMintGBPC(1e18, 100e18);
        collateralFeed.updateAnswer(87.5e8);
        (uint256 recovered, uint256 payout) = vault.previewLiquidation(borrower, type(uint256).max);
        assertEq(recovered, uint256(87.5e18) * 100 / 110);
        assertEq(payout, 1e18);
        vm.prank(liquidator);
        vault.liquidate(borrower, type(uint256).max);
        assertEq(collateral.balanceOf(liquidator), payout);
        assertEq(coin.balanceOf(liquidator), 100e18 - recovered);
        assertEq(vault.collateralBalance(borrower), 0);
        assertEq(vault.gbpcMinted(borrower), 0);
        assertEq(vault.badDebt(), 100e18 - recovered);
        assertEq(coin.totalSupply(), vault.gbpcMinted(liquidator) + vault.badDebt());

        uint256 shortfall = vault.badDebt();
        vm.expectRevert(abi.encodeWithSelector(GreatVault.GV__InvalidAmount.selector, shortfall + 1));
        vault.coverBadDebt(shortfall + 1);
        vm.prank(liquidator);
        vault.coverBadDebt(shortfall);
        assertEq(vault.badDebt(), 0);
        assertEq(coin.totalSupply(), vault.gbpcMinted(liquidator));
    }

    function testUnsafeRiskParametersRejectedAtDeploymentAndUpdates() public {
        vm.expectRevert(GreatVault.GV__InvalidRiskParameters.selector);
        vault.setLiquidationSpread(25);
        vm.expectRevert(GreatVault.GV__InvalidRiskParameters.selector);
        vault.setLiquidationThreshold(91);
        SafetyCollateral other = new SafetyCollateral(18);
        vm.expectRevert(GreatVault.GV__InvalidRiskParameters.selector);
        master.deployVault(address(other), address(collateralFeed), 8, 1 days, 80, 30, 50);
    }

    function testOldCollateralPriceRejectsBorrowingButAllowsFullRepaymentAndExit() public {
        vm.prank(borrower);
        vault.depositCollateralAndMintGBPC(1e18, 100e18);
        (,,, uint256 updatedAt,) = collateralFeed.latestRoundData();
        vm.warp(block.timestamp + 30 days);
        gbpFeed.updateAnswer(1e8);
        vm.expectRevert(abi.encodeWithSelector(OracleLib.StalePrice.selector, address(collateralFeed), updatedAt));
        vm.prank(borrower);
        vault.mintGBPC(1);
        assertEq(vault.gbpcMinted(borrower), 100e18);
        vm.startPrank(borrower);
        coin.approve(address(vault), 100e18);
        vault.burnGBPCandWithdrawCollateral(100e18, 1e18);
        vm.stopPrank();
        assertEq(vault.gbpcMinted(borrower), 0);
        assertEq(vault.collateralBalance(borrower), 0);
        assertEq(collateral.balanceOf(borrower), 1e18);
    }

    function testInvalidOracleDataCannotMint(bool gbp, uint8 failure) public {
        failure = uint8(bound(failure, 0, 4));
        MockV3Aggregator feed = gbp ? gbpFeed : collateralFeed;
        int256 answer = gbp ? int256(1e8) : int256(125e8);
        uint256 timestamp = block.timestamp;
        bytes memory expected;
        if (failure < 2) {
            answer = failure == 0 ? int256(0) : int256(-1);
            expected = abi.encodeWithSelector(OracleLib.InvalidPrice.selector, address(feed), answer);
        } else {
            if (failure == 2) timestamp = 0;
            if (failure == 3) timestamp = block.timestamp + 1;
            if (failure == 4) {
                vm.warp(block.timestamp + 2 days);
                (gbp ? collateralFeed : gbpFeed).updateAnswer(gbp ? int256(125e8) : int256(1e8));
            }
            expected = abi.encodeWithSelector(OracleLib.StalePrice.selector, address(feed), timestamp);
        }
        feed.updateRoundData(2, answer, timestamp, timestamp);
        vm.expectRevert(expected);
        vm.prank(borrower);
        vault.depositCollateralAndMintGBPC(1e18, 100e18);
        assertEq(vault.collateralBalance(borrower), 0);
        assertEq(vault.gbpcMinted(borrower), 0);
        assertEq(collateral.balanceOf(borrower), 1e18);
    }

    function testTaxedCollateralCreditsOnlyReceivedAssets() public {
        SafetyCollateral taxed = new SafetyCollateral(18);
        taxed.setTax(30);
        master.deployVault(address(taxed), address(collateralFeed), 8, 1 days, 80, 10, 50);
        GreatVault taxedVault = GreatVault(master.collateralVault(address(taxed)));
        taxed.mint(borrower, 1e18);
        vm.startPrank(borrower);
        taxed.approve(address(taxedVault), 1e18);
        vm.expectRevert(GreatVault.GV__HealthFactorBroken.selector);
        taxedVault.depositCollateralAndMintGBPC(1e18, 100e18);
        assertEq(taxed.balanceOf(borrower), 1e18);
        taxedVault.depositCollateralAndMintGBPC(1e18, 70e18);
        vm.stopPrank();
        assertEq(taxedVault.collateralBalance(borrower), 0.7e18);
        assertEq(taxed.balanceOf(address(taxedVault)), 0.7e18);
        assertEq(taxedVault.gbpcMinted(borrower), 70e18);
        assertEq(taxedVault.healthFactor(borrower), 1e18);
        vm.startPrank(borrower);
        coin.approve(address(taxedVault), 70e18);
        vm.expectRevert(GreatVault.GV__UnsupportedCollateralTransfer.selector);
        taxedVault.burnGBPCandWithdrawCollateral(70e18, 0.7e18);
        vm.stopPrank();
        assertEq(taxedVault.gbpcMinted(borrower), 70e18);
        assertEq(coin.balanceOf(borrower), 70e18);
        assertEq(taxedVault.collateralBalance(borrower), 0.7e18);
        assertEq(taxed.balanceOf(address(taxedVault)), 0.7e18);
        taxed.setTax(0);
        vm.prank(borrower);
        taxedVault.burnGBPCandWithdrawCollateral(70e18, 0.7e18);
        assertEq(taxed.balanceOf(borrower), 0.7e18);
    }

    function testLowDecimalCollateralRetainsSmallPricesForLiquidation() public {
        SafetyCollateral sixDecimals = new SafetyCollateral(6);
        MockV3Aggregator feed = new MockV3Aggregator(8, 199);
        master.deployVault(address(sixDecimals), address(feed), 8, 1 days, 80, 10, 50);
        GreatVault smallVault = GreatVault(master.collateralVault(address(sixDecimals)));
        sixDecimals.mint(borrower, 1e12);
        vm.startPrank(borrower);
        sixDecimals.approve(address(smallVault), 1e12);
        smallVault.depositCollateralAndMintGBPC(1e12, 1e18);
        vm.stopPrank();
        feed.updateAnswer(99);
        assertEq(smallVault.collateralToGbp(1e12), 0.99e18);
        assertEq(smallVault.gbpToCollateral(0.99e18), 1e12);
        vm.startPrank(liquidator);
        coin.approve(address(smallVault), type(uint256).max);
        smallVault.liquidate(borrower, 1e18);
        vm.stopPrank();
        assertEq(sixDecimals.balanceOf(liquidator), 1e12);
        assertEq(smallVault.badDebt(), 0.1e18);
        assertEq(smallVault.gbpcMinted(borrower), 0);
    }

    function testOutgoingSurchargeCannotConsumePooledCollateral() public {
        vm.prank(borrower);
        vault.depositCollateral(1e18);
        uint256 initialAssets = collateral.balanceOf(address(vault));
        collateral.setTax(10);
        collateral.setChargeExtra(true);
        vm.expectRevert(GreatVault.GV__UnsupportedCollateralTransfer.selector);
        vm.prank(borrower);
        vault.withdrawCollateral(0.5e18);
        assertEq(vault.collateralBalance(borrower), 1e18);
        assertEq(collateral.balanceOf(address(vault)), initialAssets);
        assertEq(collateral.balanceOf(borrower), 0);
    }

    function testNestedDepositCannotInflateReceivedCollateral() public {
        collateral.prepareNestedDeposit(address(vault), 1e18);
        vm.prank(borrower);
        vault.depositCollateralAndMintGBPC(1e18, 100e18);
        assertEq(vault.collateralBalance(borrower), 1e18);
        assertEq(vault.collateralBalance(address(collateral)), 0);
        assertEq(collateral.balanceOf(address(vault)), 3e18);
        vm.expectRevert(GreatVault.GV__HealthFactorBroken.selector);
        vm.prank(borrower);
        vault.mintGBPC(1);
    }

    function testIndivisibleCollateralCannotBeListed() public {
        SafetyCollateral wholeToken = new SafetyCollateral(0);
        vm.expectRevert(abi.encodeWithSelector(GreatVault.GV__UnsupportedCollateralDecimals.selector, 0));
        master.deployVault(address(wholeToken), address(collateralFeed), 8, 1 days, 80, 10, 50);
    }

    function testInvalidFeedConfigurationCannotReplaceWorkingOracle(bool gbp, uint8 failure) public {
        failure = uint8(bound(failure, 0, 3));
        address feed = gbp ? address(gbpFeed) : address(collateralFeed);
        USDPriceFeed memory settings = USDPriceFeed({feed: feed, decimals: 8, maxAge: 1 days});
        if (failure == 0) settings.maxAge = 0;
        if (failure == 1) settings.decimals = 9;
        if (failure == 2) settings.decimals = 19;
        if (failure == 3) settings.feed = address(0);
        if (!gbp && failure == 3) {
            vm.expectRevert(abi.encodeWithSelector(GreatVault.GV__InvalidAddress.selector, address(0)));
        } else {
            vm.expectRevert(abi.encodeWithSelector(OracleLib.InvalidPriceFeed.selector, settings.feed));
        }
        if (gbp) master.setGbpUsdPriceFeed(settings);
        else vault.setCollateralUsdPriceFeed(settings);
        vm.prank(borrower);
        vault.depositCollateralAndMintGBPC(1e18, 100e18);
        assertEq(coin.balanceOf(borrower), 100e18);
    }
}
