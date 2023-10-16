// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
    using SafeERC20 for IERC20;
    using Math for uint256;

    error GV__InvalidCollateral(address collateral);
    error GV__InvalidAmount(uint256 amount);
    error GV__InvalidAddress(address address_);
    error GV__InvalidPercentage(uint8 percentage);
    error GV__HealthFactorBroken();

    USDPriceFeed private _collateralUsdPriceFeed;

    uint64 private constant GBPC_DECIMALS = 18;
    uint64 private constant PRECISION = 1e18;
    uint64 private constant ONE_HUNDRED_PERCENT = 100;

    uint8 private _liquidationSpread;
    uint8 private _liquidationThreshold;
    uint8 private _closeFactor;

    mapping(address account => uint256 balance) private _collateralBalances;
    mapping(address account => uint256 gbpcMinted) private _gbpcMinted;
    IERC20 private _collateral;
    VaultMaster private _master;

    event CollateralDeposited(address indexed by, address indexed receiver, address indexed collateral, uint256 amount);
    event GBPCMinted(address indexed by, address indexed receiver, uint256 amount);

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert GV__InvalidAmount(amount);
        _;
    }

    modifier nonZeroAddress(address address_) {
        if (address_ == address(0)) revert GV__InvalidAddress(address_);
        _;
    }

    modifier validPercentage(uint8 percentage) {
        if (percentage > 100) revert GV__InvalidPercentage(percentage);
        _;
    }

    constructor(
        address owner,
        address collateral,
        address usdPriceFeed,
        uint8 priceFeedDecimals,
        uint8 liquidationSpread,
        uint8 liquidationThreshold,
        uint8 closeFactor
    ) Ownable(owner) {
        _master = VaultMaster(msg.sender);
        _collateral = IERC20(collateral);
        _collateralUsdPriceFeed = USDPriceFeed({feed: usdPriceFeed, decimals: priceFeedDecimals});
        _liquidationSpread = liquidationSpread;
        _liquidationThreshold = liquidationThreshold;
        _closeFactor = closeFactor;
    }

    // TODO: deposit and mint at once

    function depositCollateral(uint256 amount, address receiver)
        external
        nonZeroAmount(amount)
        nonZeroAddress(receiver)
        whenNotPaused
    {
        IERC20 collateral = _collateral;
        _collateralBalances[receiver] += amount;

        emit CollateralDeposited(msg.sender, receiver, address(collateral), amount);

        collateral.safeTransferFrom(msg.sender, address(this), amount);
    }

    function mintGBPC(address receiver, uint256 amount)
        external
        nonZeroAddress(receiver)
        nonZeroAmount(amount)
        whenNotPaused
    {
        if (amount > _borrowingCapacity(msg.sender)) revert GV__HealthFactorBroken();

        _gbpcMinted[msg.sender] += amount;

        emit GBPCMinted(msg.sender, receiver, amount);

        gbpCoin().mint(receiver, amount);
    }

    // TODO: redeem and burn at once

    function collateralToGBP(uint256 amount) external view returns (uint256) {
        return _collateralToGBP(amount);
    }

    function _collateralToGBP(uint256 amount) private view returns (uint256 gbpPrice) {
        USDPriceFeed memory collateralUsdPriceFeed = _collateralUsdPriceFeed;
        USDPriceFeed memory gbpUsdPriceFeed = _master.gbpUsdPriceFeed();
        uint8 collateralDecimals = IERC20Metadata(address(_collateral)).decimals();

        (, int256 collateralToUsdAnswer,,,) = AggregatorV3Interface(collateralUsdPriceFeed.feed).latestRoundData(); //
        (, int256 gbpToUsdAnswer,,,) = AggregatorV3Interface(gbpUsdPriceFeed.feed).latestRoundData();

        uint256 assetUsdPrice = uint256(collateralToUsdAnswer) * 10 ** (GBPC_DECIMALS - collateralUsdPriceFeed.decimals);
        uint256 gbpUsdPrice = uint256(gbpToUsdAnswer) * 10 ** (GBPC_DECIMALS - gbpUsdPriceFeed.decimals);

        gbpPrice = assetUsdPrice.mulDiv(amount * 10 ** GBPC_DECIMALS - collateralDecimals, gbpUsdPrice);
    }

    function _borrowingCapacity(address account) private view returns (uint256 borrowingCapacity) {
        uint256 collateralBalance = _collateralBalances[account];
        uint256 collateralGbpValue = _collateralToGBP(collateralBalance);

        borrowingCapacity = collateralGbpValue.mulDiv(_liquidationThreshold, ONE_HUNDRED_PERCENT);
    }

    function gbpCoin() public view returns (GBPCoin) {
        return _master.gbpCoin();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
