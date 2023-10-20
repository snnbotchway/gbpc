// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

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
contract GreatVault is Ownable, Pausable {
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;
    using Math for uint8;

    error GV__InvalidAmount(uint256 amount);
    error GV__InvalidAddress(address address_);
    error GV__HealthFactorBroken();
    error GV__HealthFactorNotBroken(uint256 healthFactor);
    error GV__CloseFactorAmountExceeded(uint256 closeFactorAmount);
    error GV__PercentageCannotBeMoreThan100(uint8 percentage);

    USDPriceFeed private _collateralUsdPriceFeed;

    uint64 private constant PRECISION = 1e18;
    uint64 private constant MIN_HEALTH_FACTOR = 1e18;
    uint8 private constant ONE_HUNDRED_PERCENT = 100;

    uint8 private _liquidationSpread;
    uint8 private _liquidationThreshold;
    uint8 private _closeFactor;

    mapping(address account => uint256 balance) private _collateralBalances;
    mapping(address account => uint256 gbpcMinted) private _gbpcMinted;
    IERC20Metadata private immutable _collateral;
    VaultMaster private immutable _master;

    event CollateralDeposited(address indexed by, address indexed receiver, uint256 amount);
    event GBPCMinted(address indexed by, address indexed receiver, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed receiver, uint256 amount);
    event GBPCBurned(address indexed debtor, address indexed gbpcFrom, uint256 amount);
    event Liquidated(address indexed liquidated, address indexed liquidator, uint256 collateralRedeemed, uint256 gbpcRepaid);

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

    function depositCollateralAndMintGBPC(address receiver, uint256 collateralAmount, uint256 gbpcAmount) external {
        depositCollateral(receiver, collateralAmount);
        mintGBPC(receiver, gbpcAmount);
    }

    function depositCollateral(address receiver, uint256 amount)
        public
        nonZeroAmount(amount)
        nonZeroAddress(receiver)
        whenNotPaused
    {
        _collateralBalances[receiver] += amount;
        emit CollateralDeposited(msg.sender, receiver, amount);

        _collateral.safeTransferFrom(msg.sender, address(this), amount);
    }

    function mintGBPC(address receiver, uint256 amount)
        public
        nonZeroAddress(receiver)
        nonZeroAmount(amount)
        whenNotPaused
    {
        if (amount > _borrowingCapacity(msg.sender)) revert GV__HealthFactorBroken();

        _gbpcMinted[msg.sender] += amount;

        emit GBPCMinted(msg.sender, receiver, amount);

        gbpCoin().mint(receiver, amount);
    }

    function burnGBPCandRedeemCollateral(address receiver, uint256 collateralAmount, uint256 gbpcAmount) external {
        _burnGBPC(msg.sender, msg.sender, gbpcAmount);
        _redeemCollateral(msg.sender, receiver, collateralAmount);
        _checkHealthFactor(msg.sender);
    }

    function redeemCollateral(address receiver, uint256 amount)
        external
        nonZeroAddress(receiver)
        nonZeroAmount(amount)
        whenNotPaused
    {
        _redeemCollateral(msg.sender, receiver, amount);
        _checkHealthFactor(msg.sender);
    }

    function burnGBPC(uint256 amount) external nonZeroAmount(amount) whenNotPaused {
        _burnGBPC(msg.sender, msg.sender, amount);
    }

    function liquidate(address account, uint256 gbpcToRepay)
        external
        nonZeroAddress(account)
        nonZeroAmount(gbpcToRepay)
        whenNotPaused
    {
        uint256 healthFactor = _healthFactor(account);
        if (healthFactor >= MIN_HEALTH_FACTOR) revert GV__HealthFactorNotBroken(healthFactor);

        uint256 accountDebt = _gbpcMinted[account];
        uint256 closeFactorAmount = _closeFactor.mulDiv(accountDebt, ONE_HUNDRED_PERCENT);

        if (gbpcToRepay > closeFactorAmount) revert GV__CloseFactorAmountExceeded(closeFactorAmount);

        uint256 liquidatorCollateral = _calculateLiquidatorCollateral(gbpcToRepay);

        emit Liquidated(account, msg.sender, liquidatorCollateral, gbpcToRepay);

        _burnGBPC(account, msg.sender, gbpcToRepay);
        _redeemCollateral(account, msg.sender, liquidatorCollateral);
    }

    function collateralToGBP(uint256 amount) external view returns (uint256) {
        return _collateralToGBP(amount);
    }

    function _redeemCollateral(address from, address receiver, uint256 amount)
        private
        nonZeroAddress(from)
        nonZeroAddress(receiver)
        nonZeroAmount(amount)
        whenNotPaused
    {
        _collateralBalances[from] -= amount;

        emit CollateralRedeemed(from, receiver, amount);

        _collateral.safeTransfer(receiver, amount);
    }

    function _burnGBPC(address debtor, address gbpcFrom, uint256 amount)
        private
        nonZeroAddress(debtor)
        nonZeroAddress(gbpcFrom)
        nonZeroAmount(amount)
        whenNotPaused
    {
        _gbpcMinted[debtor] -= amount;

        emit GBPCBurned(debtor, gbpcFrom, amount);

        gbpCoin().burnFrom(gbpcFrom, amount);
    }

    function _calculateLiquidatorCollateral(uint256 gbpcToRepay) private view returns (uint256 liquidatorCollateral) {
        uint256 collateralGbpcPrice = _collateralToGBP(1 * 10 ** _collateral.decimals());

        uint256 liquidatorCollateralPrice =
            collateralGbpcPrice.mulDiv(ONE_HUNDRED_PERCENT, ONE_HUNDRED_PERCENT + _liquidationSpread);

        liquidatorCollateral = gbpcToRepay.mulDiv(collateralGbpcPrice, liquidatorCollateralPrice);
    }

    // TODO: Possible 0 denominators, zero amounts and addresses, whenNotPaused

    function _collateralToGBP(uint256 amount) private view returns (uint256 gbpPrice) {
        USDPriceFeed memory collateralUsdPriceFeed_ = _collateralUsdPriceFeed;
        USDPriceFeed memory gbpUsdPriceFeed = _master.gbpUsdPriceFeed();
        uint8 gbpcDecimals = gbpCoin().decimals();

        (, int256 collateralToUsdAnswer,,,) = AggregatorV3Interface(collateralUsdPriceFeed_.feed).latestRoundData();
        (, int256 gbpToUsdAnswer,,,) = AggregatorV3Interface(gbpUsdPriceFeed.feed).latestRoundData();

        uint256 assetUsdPrice = uint256(collateralToUsdAnswer) * 10 ** (gbpcDecimals - collateralUsdPriceFeed_.decimals);
        uint256 gbpUsdPrice = uint256(gbpToUsdAnswer) * 10 ** (gbpcDecimals - gbpUsdPriceFeed.decimals);

        gbpPrice = assetUsdPrice.mulDiv(amount * 10 ** (gbpcDecimals - _collateral.decimals()), gbpUsdPrice);
    }

    function _borrowingCapacity(address account) private view returns (uint256 borrowingCapacity) {
        uint256 collateralGbpValue = _collateralToGBP(_collateralBalances[account]);
        borrowingCapacity = collateralGbpValue.mulDiv(_liquidationThreshold, ONE_HUNDRED_PERCENT);
    }

    function _checkHealthFactor(address account) private view {
        if (_healthFactor(account) < MIN_HEALTH_FACTOR) revert GV__HealthFactorBroken();
    }

    function _healthFactor(address account) private view returns (uint256 healthFactor) {
        uint256 debt = _gbpcMinted[account];
        if (debt == 0) return type(uint256).max;
        healthFactor = _borrowingCapacity(account).mulDiv(PRECISION, debt);
    }

    function gbpCoin() public view returns (GBPCoin) {
        return GBPCoin(_master._gbpCoin());
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setLiquidationSpread(uint8 newSpread) external nonZeroAmount(newSpread) onlyOwner whenNotPaused {
        _liquidationSpread = newSpread;
    }

    function setLiquidationThreshold(uint8 newThreshold) external nonZeroAmount(newThreshold) onlyOwner whenNotPaused {
        _liquidationThreshold = newThreshold;
    }

    function setCloseFactor(uint8 newFactor) external nonZeroAmount(newFactor) onlyOwner whenNotPaused {
        _closeFactor = newFactor;
    }

    function setCollateralUsdPriceFeed(address newFeed, uint8 newDecimals)
        external
        nonZeroAddress(newFeed)
        onlyOwner
        whenNotPaused
    {
        _collateralUsdPriceFeed.feed = newFeed;
        _collateralUsdPriceFeed.decimals = newDecimals;
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

    function collateralUsdPriceFeed() external view returns (address, uint256) {
        return (_collateralUsdPriceFeed.feed, _collateralUsdPriceFeed.decimals);
    }
}
