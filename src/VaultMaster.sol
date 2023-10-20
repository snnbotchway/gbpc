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
    error GV__InvalidAddress(address address_);
    error GC__DuplicateCollateral(address collateral);
    error GV__IncompatibleCollateral();
    error GV__IncompatiblePriceFeed();

    USDPriceFeed private _gbpUsdPriceFeed;
    mapping(address collateral => address vault) private _vaults;
    GBPCoin public _gbpCoin;

    event VaultDeployed(address indexed collateral, address indexed vault);

    modifier nonZeroAddress(address address_) {
        if (address_ == address(0)) revert GV__InvalidAddress(address_);
        _;
    }

    constructor(address greatDAO_, address gbpCoin_, address gbpUsdPriceFeed_, uint8 gbpUsdPriceFeedDecimals_)
        Ownable(greatDAO_)
        nonZeroAddress(greatDAO_)
    {
        _gbpCoin = GBPCoin(gbpCoin_);

        if (_gbpCoin.decimals() < gbpUsdPriceFeedDecimals_) revert GV__IncompatiblePriceFeed();

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
        uint8 liquidationThreshold,
        uint8 liquidationSpread,
        uint8 closeFactor
    ) external onlyOwner {
        if (_vaults[collateral] != address(0)) revert GC__DuplicateCollateral(collateral);

        GBPCoin gbpCoin_ = _gbpCoin;

        /// @custom:audit Collateral to GBPC conversion in the vault assumes the GBPC decimals are greater than or
        /// equal to the decimals of the Collateral and Pricefeed.
        if (gbpCoin_.decimals() < IERC20Metadata(collateral).decimals()) revert GV__IncompatibleCollateral();
        if (gbpCoin_.decimals() < priceFeedDecimals) revert GV__IncompatiblePriceFeed();

        address vaultOwner = owner(); // The DAO will own the vault as well.

        GreatVault vault = new GreatVault(
            vaultOwner, 
            collateral, 
            usdPriceFeed, 
            priceFeedDecimals, 
            liquidationThreshold, 
            liquidationSpread, 
            closeFactor
        );
        _vaults[collateral] = address(vault);

        emit VaultDeployed(collateral, address(vault));

        bytes32 minterRole = gbpCoin_.MINTER_ROLE();
        gbpCoin_.grantRole(minterRole, address(vault));
    }

    function gbpUsdPriceFeed() external view returns (USDPriceFeed memory) {
        return _gbpUsdPriceFeed;
    }

    function gbpCoin() external view returns (address) {
        return address(_gbpCoin);
    }

    function collateralVault(address collateral) external view returns (address) {
        return _vaults[collateral];
    }
}
