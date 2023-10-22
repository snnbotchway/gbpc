// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GBPCoin} from "./GBPCoin.sol";
import {VaultMaster} from "./VaultMaster.sol";
import {USDPriceFeed} from "./utils/Structs.sol";

/**
 * @title Great Vault - Named after The Great Britain
 * @author Solomon Botchway
 * @notice This contract represents the Great Vault, which is responsible for minting and burning GBPC as needed.
 * @dev The GreatVault owns the GBPC token, and is the only contract that can mint or burn GBPC.
 * @custom:security-contact Contact: solomonbotchway7@gmail.com
 */
contract GreatVault is Ownable {
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;

    error GV__InvalidAmount(uint256 amount);
    error GV__InvalidAddress(address address_);
    error GV__HealthFactorBroken();
    error GV__HealthFactorNotBroken(uint256 healthFactor);
    error GV__HealthFactorNotIncreased(uint256 initialHealthFactor, uint256 finalHealthFactor);
    error GV__CloseFactorAmountExceeded(uint256 closeFactorAmount);
    error GV__PercentageCannotBeMoreThan100(uint8 percentage);

    USDPriceFeed private _collateralUsdPriceFeed;
    IERC20Metadata private immutable _collateral;
    VaultMaster private immutable _master;
    mapping(address account => uint256 balance) private _collateralBalances;
    mapping(address account => uint256 gbpcMinted) private _gbpcMinted;

    uint64 private constant MIN_HEALTH_FACTOR = 1e18;
    uint64 private constant PRECISION = 1e18;
    uint8 private constant ONE_HUNDRED_PERCENT = 100;

    uint8 private _liquidationSpread;
    uint8 private _liquidationThreshold;
    uint8 private _closeFactor;

    event CollateralDeposited(address indexed by, uint256 amount);
    event GBPCMinted(address indexed by, uint256 amount);
    event CollateralWithdrawn(address indexed from, address indexed receiver, uint256 amount);
    event GBPCBurned(address indexed debtor, address indexed gbpcFrom, uint256 amount);
    event Liquidated(
        address indexed liquidated, address indexed liquidator, uint256 collateralWithdrawn, uint256 gbpcRepaid
    );
    event LiquidationSpreadSet(uint8 newSpread);
    event LiquidationThresholdSet(uint8 newThreshold);
    event CloseFactorSet(uint8 newFactor);
    event CollateralUsdPriceFeedSet(USDPriceFeed newPriceFeed);

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert GV__InvalidAmount(amount);
        _;
    }

    modifier nonZeroAddress(address address_) {
        if (address_ == address(0)) revert GV__InvalidAddress(address_);
        _;
    }

    modifier notMoreThan100(uint8 percentage) {
        if (percentage > 100) revert GV__PercentageCannotBeMoreThan100(percentage);
        _;
    }

    constructor(
        address owner_,
        address collateral_,
        address usdPriceFeed_,
        uint8 priceFeedDecimals_,
        uint8 liquidationThreshold_,
        uint8 liquidationSpread_,
        uint8 closeFactor_
    )
        Ownable(owner_)
        nonZeroAddress(collateral_)
        nonZeroAddress(usdPriceFeed_)
        nonZeroAmount(liquidationSpread_)
        nonZeroAmount(liquidationThreshold_)
        nonZeroAmount(closeFactor_)
        notMoreThan100(liquidationSpread_)
        notMoreThan100(liquidationThreshold_)
        notMoreThan100(closeFactor_)
    {
        _master = VaultMaster(msg.sender);
        _collateral = IERC20Metadata(collateral_);
        _collateralUsdPriceFeed = USDPriceFeed({feed: usdPriceFeed_, decimals: priceFeedDecimals_});

        _liquidationSpread = liquidationSpread_;
        _liquidationThreshold = liquidationThreshold_;
        _closeFactor = closeFactor_;
    }

    function depositCollateralAndMintGBPC(uint256 collateralAmount, uint256 gbpcAmount)
        external
        nonZeroAmount(collateralAmount)
        nonZeroAmount(gbpcAmount)
    {
        depositCollateral(collateralAmount);
        mintGBPC(gbpcAmount);
    }

    function burnGBPCandWithdrawCollateral(uint256 gbpcAmount, uint256 collateralAmount)
        external
        nonZeroAmount(collateralAmount)
        nonZeroAmount(gbpcAmount)
    {
        _burnGBPC(msg.sender, msg.sender, gbpcAmount);
        _withdrawCollateral(msg.sender, msg.sender, collateralAmount);
        _checkHealthFactor(msg.sender);
    }

    function withdrawCollateral(uint256 amount) external nonZeroAmount(amount) {
        _withdrawCollateral(msg.sender, msg.sender, amount);
        _checkHealthFactor(msg.sender);
    }

    function burnGBPC(uint256 amount) external nonZeroAmount(amount) {
        _burnGBPC(msg.sender, msg.sender, amount);
    }

    function liquidate(address accountToLiquidate, uint256 gbpcToRepay)
        external
        nonZeroAddress(accountToLiquidate)
        nonZeroAmount(gbpcToRepay)
    {
        uint256 initialHealthFactor = _healthFactor(accountToLiquidate);
        if (initialHealthFactor >= MIN_HEALTH_FACTOR) revert GV__HealthFactorNotBroken(initialHealthFactor);

        uint256 accountDebt = _gbpcMinted[accountToLiquidate];
        uint256 closeFactorAmount = accountDebt.mulDiv(_closeFactor, ONE_HUNDRED_PERCENT);

        if (gbpcToRepay > closeFactorAmount) revert GV__CloseFactorAmountExceeded(closeFactorAmount);

        uint256 liquidatorCollateral = previewLiquidate(gbpcToRepay);

        emit Liquidated(accountToLiquidate, msg.sender, liquidatorCollateral, gbpcToRepay);

        _burnGBPC(accountToLiquidate, msg.sender, gbpcToRepay);
        _withdrawCollateral(accountToLiquidate, msg.sender, liquidatorCollateral);

        uint256 finalHealthFactor = _healthFactor(accountToLiquidate);
        if (!(finalHealthFactor > initialHealthFactor)) {
            revert GV__HealthFactorNotIncreased(initialHealthFactor, finalHealthFactor);
        }
    }

    function setLiquidationSpread(uint8 newSpread) external nonZeroAmount(newSpread) notMoreThan100(newSpread) onlyOwner {
        _liquidationSpread = newSpread;
        emit LiquidationSpreadSet(newSpread);
    }

    function setLiquidationThreshold(uint8 newThreshold)
        external
        nonZeroAmount(newThreshold)
        notMoreThan100(newThreshold)
        onlyOwner
    {
        _liquidationThreshold = newThreshold;
        emit LiquidationThresholdSet(newThreshold);
    }

    function setCloseFactor(uint8 newFactor) external nonZeroAmount(newFactor) notMoreThan100(newFactor) onlyOwner {
        _closeFactor = newFactor;
        emit CloseFactorSet(newFactor);
    }

    function setCollateralUsdPriceFeed(USDPriceFeed calldata newPriceFeed)
        external
        nonZeroAddress(newPriceFeed.feed)
        onlyOwner
    {
        _collateralUsdPriceFeed = newPriceFeed;
        emit CollateralUsdPriceFeedSet(newPriceFeed);
    }

    function depositCollateral(uint256 amount) public nonZeroAmount(amount) {
        _collateralBalances[msg.sender] += amount;

        emit CollateralDeposited(msg.sender, amount);

        _collateral.safeTransferFrom(msg.sender, address(this), amount);
    }

    function mintGBPC(uint256 amount) public nonZeroAmount(amount) {
        _gbpcMinted[msg.sender] += amount;
        _checkHealthFactor(msg.sender);

        emit GBPCMinted(msg.sender, amount);

        gbpCoin().mint(msg.sender, amount);
    }

    function _withdrawCollateral(address from, address receiver, uint256 amount) private {
        _collateralBalances[from] -= amount;

        emit CollateralWithdrawn(from, receiver, amount);

        _collateral.safeTransfer(receiver, amount);
    }

    function _burnGBPC(address debtor, address gbpcFrom, uint256 amount) private {
        _gbpcMinted[debtor] -= amount;

        emit GBPCBurned(debtor, gbpcFrom, amount);

        gbpCoin().burnFrom(gbpcFrom, amount);
    }

    // TODO: Possible 0 denominators, zero amounts and addresses, view functions no revert

    function _collateralToGbp(uint256 collateralValue) private view returns (uint256 gbpValue) {
        USDPriceFeed memory collaUsdPriceFeed = _collateralUsdPriceFeed;
        USDPriceFeed memory gbpUsdPriceFeed = _master.gbpUsdPriceFeed();
        uint8 gbpcDecimals = gbpCoin().decimals();
        uint8 collaDecimals = _collateral.decimals();

        /// @custom:audit What to do if prices are stale?
        (, int256 collaUsdAnswer,,,) = AggregatorV3Interface(collaUsdPriceFeed.feed).latestRoundData();
        (, int256 gbpUsdAnswer,,,) = AggregatorV3Interface(gbpUsdPriceFeed.feed).latestRoundData();

        uint256 collateralUsdPrice = _syncDecimals(uint256(collaUsdAnswer), collaUsdPriceFeed.decimals, gbpcDecimals);
        uint256 gbpUsdPrice = _syncDecimals(uint256(gbpUsdAnswer), gbpUsdPriceFeed.decimals, gbpcDecimals);

        gbpValue = collateralUsdPrice.mulDiv(collateralValue, gbpUsdPrice);
        gbpValue = _syncDecimals(gbpValue, collaDecimals, gbpcDecimals);
    }

    function _gbpToCollateral(uint256 gbpValue) private view returns (uint256 collateralValue) {
        USDPriceFeed memory collaUsdPriceFeed = _collateralUsdPriceFeed;
        USDPriceFeed memory gbpUsdPriceFeed = _master.gbpUsdPriceFeed();
        uint8 gbpcDecimals = gbpCoin().decimals();
        uint8 collaDecimals = _collateral.decimals();

        /// @custom:audit What to do if prices are stale?
        (, int256 collaUsdAnswer,,,) = AggregatorV3Interface(collaUsdPriceFeed.feed).latestRoundData();
        (, int256 gbpUsdAnswer,,,) = AggregatorV3Interface(gbpUsdPriceFeed.feed).latestRoundData();

        uint256 collateralUsdPrice = _syncDecimals(uint256(collaUsdAnswer), collaUsdPriceFeed.decimals, collaDecimals);
        uint256 gbpUsdPrice = _syncDecimals(uint256(gbpUsdAnswer), gbpUsdPriceFeed.decimals, collaDecimals);

        collateralValue = gbpUsdPrice.mulDiv(gbpValue, collateralUsdPrice);
        collateralValue = _syncDecimals(collateralValue, gbpcDecimals, collaDecimals);
    }

    function _borrowingCapacity(address account) private view returns (uint256 maxBorrow) {
        uint256 collateralGbpValue = _collateralToGbp(_collateralBalances[account]);
        maxBorrow = collateralGbpValue.mulDiv(_liquidationThreshold, ONE_HUNDRED_PERCENT);
    }

    function _checkHealthFactor(address account) private view {
        if (_healthFactor(account) < MIN_HEALTH_FACTOR) revert GV__HealthFactorBroken();
    }

    function _healthFactor(address account) private view returns (uint256 healthFactor_) {
        uint256 debt = _gbpcMinted[account];
        if (debt == 0) return type(uint256).max;
        healthFactor_ = _borrowingCapacity(account).mulDiv(PRECISION, debt);
    }

    function _syncDecimals(uint256 value, uint8 fromDecimals, uint8 toDecimals) private pure returns (uint256) {
        if (fromDecimals > toDecimals) return value / 10 ** (fromDecimals - toDecimals);
        if (fromDecimals < toDecimals) return value * 10 ** (toDecimals - fromDecimals);
        return value;
    }

    function previewDepositCollateral(uint256 collateralAmount) external view returns (uint256 maxMintableGbpc) {
        uint256 collateralGbpValue = _collateralToGbp(collateralAmount);
        maxMintableGbpc = collateralGbpValue.mulDiv(_liquidationThreshold, ONE_HUNDRED_PERCENT);
    }

    function previewMintGBPC(uint256 gbpcAmount) external view returns (uint256 minCollateralDeposit) {
        uint256 collateralGbpValue = gbpcAmount.mulDiv(ONE_HUNDRED_PERCENT, _liquidationThreshold);
        minCollateralDeposit = _gbpToCollateral(collateralGbpValue) + 1;
    }

    function liquidationSpread() external view returns (uint8) {
        return _liquidationSpread;
    }

    function liquidationThreshold() external view returns (uint8) {
        return _liquidationThreshold;
    }

    function closeFactor() external view returns (uint8) {
        return _closeFactor;
    }

    function collateralBalance(address account) external view returns (uint256) {
        return _collateralBalances[account];
    }

    function gbpcMinted(address account) external view returns (uint256) {
        return _gbpcMinted[account];
    }

    function collateral() external view returns (address) {
        return address(_collateral);
    }

    function vaultMaster() external view returns (address) {
        return address(_master);
    }

    function collateralUsdPriceFeed() external view returns (USDPriceFeed memory) {
        return _collateralUsdPriceFeed;
    }

    function collateralToGbp(uint256 amount) external view returns (uint256) {
        return _collateralToGbp(amount);
    }

    function gbpToCollateral(uint256 amount) external view returns (uint256) {
        return _gbpToCollateral(amount);
    }

    function borrowingCapacity(address account) external view returns (uint256) {
        return _borrowingCapacity(account);
    }

    function healthFactor(address account) external view returns (uint256) {
        return _healthFactor(account);
    }

    function previewLiquidate(uint256 gbpcToRepay) public view returns (uint256) {
        uint256 gbpValueOfCollaToClaim = gbpcToRepay.mulDiv(ONE_HUNDRED_PERCENT + _liquidationSpread, ONE_HUNDRED_PERCENT);
        return _gbpToCollateral(gbpValueOfCollaToClaim);
    }

    function gbpCoin() public view returns (GBPCoin) {
        return GBPCoin(_master.gbpCoin());
    }
}
