// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {GBPCoin} from "./GBPCoin.sol";
import {GreatVault} from "./GreatVault.sol";
import {USDPriceFeed} from "./utils//Structs.sol";

/**
 * @title Vault Master
 * @author Solomon Botchway
 * @notice This contract represents the Vault master
 * @dev // TODO
 * @custom:security-contact Contact: solomonbotchway7@gmail.com
 */
contract VaultMaster is Ownable {
    error GV__InvalidAmount(uint256 amount);
    error GV__InvalidAddress(address address_);
    error GV__PercentageCannotBeMoreThan100(uint8 percentage);
    error GC__DuplicateCollateral(address collateral);
    error GV__IncompatibleCollateral();
    error GV__IncompatiblePriceFeed();

    USDPriceFeed private _gbpUsdPriceFeed;
    mapping(address collateral => address vault) private _vaults;
    GBPCoin public _gbpCoin;

    event VaultDeployed(address indexed collateral, address indexed vault, address usdPriceFeed, uint8 liquidationSpread);

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert GV__InvalidAmount(amount);
        _;
    }

    modifier nonZeroAddress(address address_) {
        if (address_ == address(0)) revert GV__InvalidAddress(address_);
        _;
    }

    constructor(address greatDAO_, address gbpCoin_, address gbpUsdPriceFeed_, uint8 gbpUsdPriceFeedDecimals_)
        Ownable(greatDAO_)
        nonZeroAddress(greatDAO_)
    {
        if (IERC20Metadata(_gbpCoin).decimals() < gbpUsdPriceFeedDecimals_) revert GV__IncompatiblePriceFeed();

        _gbpCoin = GBPCoin(gbpCoin_);
        _gbpUsdPriceFeed = USDPriceFeed({feed: gbpUsdPriceFeed_, decimals: gbpUsdPriceFeedDecimals_});
    }

    /**
     *
     * @param collateral Must have decimals places less than or equal to that of the GBP Coin(18)
     * @param usdPriceFeed bla
     * @param priceFeedDecimals Must be less than or equal to that of the GBP Coin(18)
     * @param liquidationSpread bla
     */
    function deployVault(
        address collateral,
        address usdPriceFeed,
        uint8 priceFeedDecimals,
        uint8 liquidationSpread,
        uint8 liquidationThreshold,
        uint8 closeFactor
    )
        external
        onlyOwner
        nonZeroAddress(collateral)
        nonZeroAddress(usdPriceFeed)
        nonZeroAmount(liquidationSpread)
        nonZeroAmount(liquidationThreshold)
        nonZeroAmount(closeFactor)
    {
        if (_vaults[collateral] != address(0)) revert GC__DuplicateCollateral(collateral);

        /// @custom:audit Collateral to GBPC conversion in the vault assumes the GBPC decimals are greater than or equal to
        /// the Collateral's decimals and the Pricefeeds' decimals.
        if (IERC20Metadata(_gbpCoin).decimals() < IERC20Metadata(collateral).decimals()) revert GV__IncompatibleCollateral();
        if (IERC20Metadata(_gbpCoin).decimals() < priceFeedDecimals) revert GV__IncompatiblePriceFeed();

        address vaultOwner = owner(); // The DAO will own the vault as well.

        GreatVault vault =
        new GreatVault(vaultOwner, collateral, usdPriceFeed, priceFeedDecimals, liquidationSpread, liquidationThreshold, closeFactor);
        _vaults[collateral] = address(vault);

        emit VaultDeployed(collateral, address(vault), usdPriceFeed, liquidationSpread);

        bytes32 minterRole = _gbpCoin.MINTER_ROLE();
        _gbpCoin.grantRole(minterRole, address(vault));
    }

    function gbpUsdPriceFeed() external view returns (USDPriceFeed memory) {
        return _gbpUsdPriceFeed;
    }

    function gbpCoin() external view returns (address) {
        return address(_gbpCoin);
    }
}
