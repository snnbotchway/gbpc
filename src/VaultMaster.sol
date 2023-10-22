// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {GBPCoin} from "./GBPCoin.sol";
import {GreatVault} from "./GreatVault.sol";
import {USDPriceFeed} from "./utils/Structs.sol";

/**
 * @title Vault Master
 * @author Solomon Botchway
 * @notice This contract represents the Vault master which is owned by the GreatDAO's timelock.
 * @custom:security-contact Contact: solomonbotchway7@gmail.com
 */
contract VaultMaster is Ownable {
    error VM__InvalidAddress(address address_);
    error VM__DuplicateCollateral(address collateral);

    mapping(address collateral => address vault) private _vaults;
    USDPriceFeed private _gbpUsdPriceFeed;
    GBPCoin private _gbpCoin;

    event VaultDeployed(address indexed collateral, address indexed vault);
    event GbpUsdPriceFeedSet(USDPriceFeed newPriceFeed);

    modifier nonZeroAddress(address address_) {
        if (address_ == address(0)) revert VM__InvalidAddress(address_);
        _;
    }

    /**
     *
     * @param greatTimeLock_ Address of the Great DAO's timelock. The owner of all deployed Great Vaults by this contract will be the timelock.
     * @param gbpCoin_ Address of the GBPC stablecoin.
     * @param gbpUsdPriceFeed_ GBP Chainlink USD price feed address.
     * @param gbpUsdPriceFeedDecimals_ GBP Chainlink USD price feed decimals.
     */
    constructor(address greatTimeLock_, address gbpCoin_, address gbpUsdPriceFeed_, uint8 gbpUsdPriceFeedDecimals_)
        Ownable(greatTimeLock_)
        nonZeroAddress(greatTimeLock_)
    {
        _gbpCoin = GBPCoin(gbpCoin_);
        _gbpUsdPriceFeed = USDPriceFeed({feed: gbpUsdPriceFeed_, decimals: gbpUsdPriceFeedDecimals_});
    }

    /**
     * Deploys a Great Vault for the specified collateral, Setting this contract's owner as the vault's owner(the DAO's timelock),
     * and granting the GBPC MINTER_ROLE to the deployed vault.
     * @param collateral Address of the ERC20 token to use as collateral for minting GBPC.
     * @param usdPriceFeed Address of the Chainlink USD Pricefeed of the collateral.
     * @param priceFeedDecimals Decimals of the Chainlink USD Pricefeed of the collateral.
     * @param liquidationThreshold The percentage at which the collateral value is counted towards the borrowing capacity.
     * Borrowing Capacity(BC) refers to the total amount of GBPC that an account is allowed to mint, given its collateral amount.
     * BC = (GBP value of collateral * Liquidation Threshold) / 100.
     * @param liquidationSpread The bonus, or discount, that a liquidator can collect when liquidating collateral. This spread incentivises
     * liquidators to act promptly once a position crosses the liquidation threshold.
     * @param closeFactor A percentage of the maximum proportion of the debt that is allowed to be repaid in a single liquidation.
     */
    function deployVault(
        address collateral,
        address usdPriceFeed,
        uint8 priceFeedDecimals,
        uint8 liquidationThreshold,
        uint8 liquidationSpread,
        uint8 closeFactor
    ) external onlyOwner {
        if (_vaults[collateral] != address(0)) revert VM__DuplicateCollateral(collateral);

        address vaultOwner = owner(); // The DAO's timelock will own the vault as well.
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

        GBPCoin gbpCoin_ = _gbpCoin;
        bytes32 minterRole = gbpCoin_.MINTER_ROLE();
        gbpCoin_.grantRole(minterRole, address(vault));
    }

    function setGbpUsdPriceFeed(USDPriceFeed calldata newPriceFeed) external onlyOwner {
        _gbpUsdPriceFeed = newPriceFeed;
        emit GbpUsdPriceFeedSet(newPriceFeed);
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
