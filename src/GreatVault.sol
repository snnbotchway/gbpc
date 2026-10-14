// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GBPCoin} from "./GBPCoin.sol";
import {VaultMaster} from "./VaultMaster.sol";
import {USDPriceFeed} from "./utils/Structs.sol";
import {OracleLib} from "./utils/OracleLib.sol";

/**
 * @title Great Vault - Named after The Great Britain.
 * @author Solomon Botchway
 * @notice This contract represents the Great Vault, which is responsible for minting and burning GBPC as needed.
 * @notice Liquidation recovers collateral after price falls; unrecoverable debt is recorded separately.
 * @dev All Great Vaults deployed by the Vault Master are minters of the GBPC token, and are the only contracts that
 * can mint or burn GBPC.
 * @custom:security-contact Contact: solomonbotchway7@gmail.com
 */
contract GreatVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;

    error GV__InvalidAmount(uint256 amount);
    error GV__InvalidAddress(address address_);
    error GV__HealthFactorBroken();
    error GV__HealthFactorNotBroken(uint256 healthFactor);
    error GV__PercentageCannotBeMoreThan100(uint8 percentage);
    error GV__UnsupportedCollateralDecimals(uint8 decimals);
    error GV__UnsupportedCollateralTransfer();
    error GV__InvalidRiskParameters();

    USDPriceFeed private _collateralUsdPriceFeed;
    IERC20Metadata private immutable _collateral;
    uint256 private immutable _collateralScale;
    VaultMaster private immutable _master;
    mapping(address account => uint256 balance) private _collateralBalances;
    mapping(address account => uint256 gbpcMinted) private _gbpcMinted;
    uint256 private _badDebt;

    uint64 private constant MIN_HEALTH_FACTOR = 1e18;
    uint64 private constant PRECISION = 1e18;
    uint8 private constant ONE_HUNDRED_PERCENT = 100;
    uint8 private constant MIN_COLLATERAL_DECIMALS = 6;

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
    event BadDebtRecorded(address indexed account, uint256 amount);
    event BadDebtCovered(address indexed by, uint256 amount);

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

    /**
     *
     * @param owner_ The Vault Owner, which will be the Great DAO's Timelock.
     * @param collateral_ Address of the ERC20 token to use as collateral for minting GBPC.
     * @param collateralUsdPriceFeed_ Collateral USD price feed, decimals, and maximum accepted age in seconds.
     * @param liquidationThreshold_ The percentage at which the collateral value is counted towards the borrowing capacity.
     * Borrowing Capacity(BC) refers to the total amount of GBPC that an account is allowed to mint, given its collateral amount.
     * BC = (GBP value of collateral * Liquidation Threshold) / 100.
     * @param liquidationSpread_ The bonus, or discount, that a liquidator can collect when liquidating collateral. This spread incentivises
     * liquidators to act promptly once a position crosses the liquidation threshold.
     * @param closeFactor_ A percentage of the maximum proportion of the debt that is allowed to be repaid in a single liquidation.
     */
    constructor(
        address owner_,
        address collateral_,
        USDPriceFeed memory collateralUsdPriceFeed_,
        uint8 liquidationThreshold_,
        uint8 liquidationSpread_,
        uint8 closeFactor_
    )
        Ownable(owner_)
        nonZeroAddress(collateral_)
        nonZeroAmount(liquidationSpread_)
        nonZeroAmount(liquidationThreshold_)
        nonZeroAmount(closeFactor_)
        notMoreThan100(liquidationSpread_)
        notMoreThan100(liquidationThreshold_)
        notMoreThan100(closeFactor_)
    {
        _validateRiskParameters(liquidationThreshold_, liquidationSpread_);
        _master = VaultMaster(msg.sender);
        _collateral = IERC20Metadata(collateral_);
        uint8 collateralDecimals = _collateral.decimals();
        if (collateralDecimals < MIN_COLLATERAL_DECIMALS || collateralDecimals > OracleLib.PRICE_DECIMALS) {
            revert GV__UnsupportedCollateralDecimals(collateralDecimals);
        }
        _collateralScale = 10 ** (OracleLib.PRICE_DECIMALS - collateralDecimals);
        OracleLib.validate(collateralUsdPriceFeed_);
        _collateralUsdPriceFeed = collateralUsdPriceFeed_;

        _liquidationSpread = liquidationSpread_;
        _liquidationThreshold = liquidationThreshold_;
        _closeFactor = closeFactor_;

        emit LiquidationThresholdSet(liquidationThreshold_);
        emit LiquidationSpreadSet(liquidationSpread_);
        emit CloseFactorSet(closeFactor_);
        emit CollateralUsdPriceFeedSet(collateralUsdPriceFeed_);
    }

    function depositCollateralAndMintGBPC(uint256 collateralAmount, uint256 gbpcAmount)
        external
        nonReentrant
        nonZeroAmount(collateralAmount)
        nonZeroAmount(gbpcAmount)
    {
        _depositCollateral(collateralAmount);
        _mintGBPC(gbpcAmount);
    }

    function burnGBPCandWithdrawCollateral(uint256 gbpcAmount, uint256 collateralAmount)
        external
        nonReentrant
        nonZeroAmount(collateralAmount)
        nonZeroAmount(gbpcAmount)
    {
        _burnGBPC(msg.sender, msg.sender, gbpcAmount);
        _withdrawCollateral(msg.sender, msg.sender, collateralAmount);
        _checkHealthFactor(msg.sender);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant nonZeroAmount(amount) {
        _withdrawCollateral(msg.sender, msg.sender, amount);
        _checkHealthFactor(msg.sender);
    }

    function burnGBPC(uint256 amount) external nonReentrant nonZeroAmount(amount) {
        _burnGBPC(msg.sender, msg.sender, amount);
    }

    /**
     * @notice Repay up to maxGbpcToRepay for collateral. The bonus is capped by the surplus of a solvent position.
     * Severely unhealthy positions allow full liquidation; insolvent positions cap repayment at recoverable collateral.
     */
    function liquidate(address accountToLiquidate, uint256 maxGbpcToRepay)
        external
        nonReentrant
        nonZeroAddress(accountToLiquidate)
        nonZeroAmount(maxGbpcToRepay)
    {
        (uint256 gbpcToRepay, uint256 liquidatorCollateral) = previewLiquidation(accountToLiquidate, maxGbpcToRepay);

        emit Liquidated(accountToLiquidate, msg.sender, liquidatorCollateral, gbpcToRepay);

        _burnGBPC(accountToLiquidate, msg.sender, gbpcToRepay);
        _withdrawCollateral(accountToLiquidate, msg.sender, liquidatorCollateral);

        if (_collateralBalances[accountToLiquidate] == 0) {
            uint256 unpaidDebt = _gbpcMinted[accountToLiquidate];
            if (unpaidDebt != 0) {
                _gbpcMinted[accountToLiquidate] = 0;
                _badDebt += unpaidDebt;
                emit BadDebtRecorded(accountToLiquidate, unpaidDebt);
            }
        }
    }

    function coverBadDebt(uint256 amount) external nonReentrant nonZeroAmount(amount) {
        if (amount > _badDebt) revert GV__InvalidAmount(amount);
        _badDebt -= amount;
        emit BadDebtCovered(msg.sender, amount);
        gbpCoin().burnFrom(msg.sender, amount);
    }

    function setLiquidationSpread(uint8 newSpread) external nonZeroAmount(newSpread) notMoreThan100(newSpread) onlyOwner {
        _validateRiskParameters(_liquidationThreshold, newSpread);
        _liquidationSpread = newSpread;
        emit LiquidationSpreadSet(newSpread);
    }

    function setLiquidationThreshold(uint8 newThreshold)
        external
        nonZeroAmount(newThreshold)
        notMoreThan100(newThreshold)
        onlyOwner
    {
        _validateRiskParameters(newThreshold, _liquidationSpread);
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
        OracleLib.validate(newPriceFeed);
        _collateralUsdPriceFeed = newPriceFeed;
        emit CollateralUsdPriceFeedSet(newPriceFeed);
    }

    function depositCollateral(uint256 amount) public nonReentrant nonZeroAmount(amount) {
        _depositCollateral(amount);
    }

    function _depositCollateral(uint256 amount) private {
        uint256 previousBalance = _collateral.balanceOf(address(this));
        _collateral.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = _collateral.balanceOf(address(this)) - previousBalance;
        if (received == 0) revert GV__InvalidAmount(received);
        _collateralBalances[msg.sender] += received;

        emit CollateralDeposited(msg.sender, received);
    }

    function mintGBPC(uint256 amount) public nonReentrant nonZeroAmount(amount) {
        _mintGBPC(amount);
    }

    function _mintGBPC(uint256 amount) private {
        _gbpcMinted[msg.sender] += amount;
        _checkHealthFactor(msg.sender);

        emit GBPCMinted(msg.sender, amount);

        gbpCoin().mint(msg.sender, amount);
    }

    function _withdrawCollateral(address from, address receiver, uint256 amount) private {
        _collateralBalances[from] -= amount;

        emit CollateralWithdrawn(from, receiver, amount);

        uint256 previousBalance = _collateral.balanceOf(address(this));
        uint256 previousReceiverBalance = _collateral.balanceOf(receiver);
        _collateral.safeTransfer(receiver, amount);
        if (
            previousBalance - _collateral.balanceOf(address(this)) != amount
                || _collateral.balanceOf(receiver) - previousReceiverBalance != amount
        ) revert GV__UnsupportedCollateralTransfer();
    }

    function _burnGBPC(address debtor, address gbpcFrom, uint256 amount) private {
        _gbpcMinted[debtor] -= amount;

        emit GBPCBurned(debtor, gbpcFrom, amount);

        gbpCoin().burnFrom(gbpcFrom, amount);
    }

    function _collateralToGbp(uint256 collateralValue) private view returns (uint256 gbpValue) {
        uint256 collateralUsdPrice = OracleLib.price(_collateralUsdPriceFeed);
        uint256 gbpUsdPrice = OracleLib.price(_master.gbpUsdPriceFeed());
        gbpValue = (collateralValue * _collateralScale).mulDiv(collateralUsdPrice, gbpUsdPrice);
    }

    function _gbpToCollateral(uint256 gbpValue) private view returns (uint256 collateralValue) {
        return _gbpToCollateral(gbpValue, Math.Rounding.Floor);
    }

    function _gbpToCollateral(uint256 gbpValue, Math.Rounding rounding) private view returns (uint256 collateralValue) {
        uint256 collateralUsdPrice = OracleLib.price(_collateralUsdPriceFeed);
        uint256 gbpUsdPrice = OracleLib.price(_master.gbpUsdPriceFeed());
        collateralValue = gbpValue.mulDiv(gbpUsdPrice, collateralUsdPrice * _collateralScale, rounding);
    }

    function _borrowingCapacity(address account) private view returns (uint256 maxBorrow) {
        uint256 collateralGbpValue = _collateralToGbp(_collateralBalances[account]);
        maxBorrow = collateralGbpValue.mulDiv(_liquidationThreshold, ONE_HUNDRED_PERCENT);
    }

    function _checkHealthFactor(address account) private view {
        if (_healthFactor(account) < MIN_HEALTH_FACTOR) revert GV__HealthFactorBroken();
    }

    function _validateRiskParameters(uint8 threshold, uint8 spread) private pure {
        if (uint256(threshold) * (ONE_HUNDRED_PERCENT + spread) >= uint256(ONE_HUNDRED_PERCENT) ** 2) {
            revert GV__InvalidRiskParameters();
        }
    }

    function _healthFactor(address account) private view returns (uint256 healthFactor_) {
        uint256 debt = _gbpcMinted[account];
        if (debt == 0) return type(uint256).max;
        healthFactor_ = _borrowingCapacity(account).mulDiv(PRECISION, debt);
    }

    function previewDepositCollateral(uint256 collateralAmount) external view returns (uint256 maxMintableGbpc) {
        uint256 collateralGbpValue = _collateralToGbp(collateralAmount);
        maxMintableGbpc = collateralGbpValue.mulDiv(_liquidationThreshold, ONE_HUNDRED_PERCENT);
    }

    function previewMintGBPC(uint256 gbpcAmount) external view returns (uint256 minCollateralDeposit) {
        uint256 collateralGbpValue = gbpcAmount.mulDiv(ONE_HUNDRED_PERCENT, _liquidationThreshold, Math.Rounding.Ceil);
        minCollateralDeposit = _gbpToCollateral(collateralGbpValue, Math.Rounding.Ceil);
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

    function badDebt() external view returns (uint256) {
        return _badDebt;
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

    /**
     * @notice Account-specific repayment and payout, including bonus and collateral caps.
     */
    function previewLiquidation(address account, uint256 maxGbpcToRepay)
        public
        view
        nonZeroAddress(account)
        nonZeroAmount(maxGbpcToRepay)
        returns (uint256 gbpcToRepay, uint256 collateralToReceive)
    {
        uint256 debt = _gbpcMinted[account];
        if (debt == 0) revert GV__HealthFactorNotBroken(type(uint256).max);
        uint256 collateralGbpValue = _collateralToGbp(_collateralBalances[account]);
        uint256 health = collateralGbpValue.mulDiv(_liquidationThreshold, ONE_HUNDRED_PERCENT).mulDiv(PRECISION, debt);
        if (health >= MIN_HEALTH_FACTOR) revert GV__HealthFactorNotBroken(health);

        uint256 criticalHealth = uint256(_liquidationThreshold) * (ONE_HUNDRED_PERCENT + _liquidationSpread) * PRECISION
            / uint256(ONE_HUNDRED_PERCENT) ** 2;
        uint256 closeFactorAmount = health <= criticalHealth ? debt : debt.mulDiv(_closeFactor, ONE_HUNDRED_PERCENT);
        gbpcToRepay = Math.min(maxGbpcToRepay, closeFactorAmount);
        if (collateralGbpValue < debt) {
            uint256 recoverableDebt =
                collateralGbpValue.mulDiv(ONE_HUNDRED_PERCENT, ONE_HUNDRED_PERCENT + _liquidationSpread);
            if (gbpcToRepay >= recoverableDebt) {
                return (recoverableDebt, _collateralBalances[account]);
            }
        }

        uint256 bonus = gbpcToRepay.mulDiv(_liquidationSpread, ONE_HUNDRED_PERCENT);
        if (collateralGbpValue >= debt) {
            bonus = Math.min(bonus, gbpcToRepay.mulDiv(collateralGbpValue - debt, debt));
        }
        collateralToReceive = _gbpToCollateral(gbpcToRepay + bonus);
        if (collateralToReceive == 0) revert GV__InvalidAmount(collateralToReceive);
    }

    function gbpCoin() public view returns (GBPCoin) {
        return GBPCoin(_master.gbpCoin());
    }
}
