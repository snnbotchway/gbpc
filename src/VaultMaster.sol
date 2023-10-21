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
 * @notice This contract represents the Vault master
 * @dev // TODO
 * @custom:security-contact Contact: solomonbotchway7@gmail.com
 */
contract VaultMaster is Ownable {
    error VM__InvalidAddress(address address_);
    error VM__DuplicateCollateral(address collateral);

    mapping(address collateral => address vault) private _vaults;
    USDPriceFeed private _gbpUsdPriceFeed;
    GBPCoin private _gbpCoin;

    event VaultDeployed(address indexed collateral, address indexed vault);

    modifier nonZeroAddress(address address_) {
        if (address_ == address(0)) revert VM__InvalidAddress(address_);
        _;
    }

    constructor(address greatTimeLock_, address gbpCoin_, address gbpUsdPriceFeed_, uint8 gbpUsdPriceFeedDecimals_)
        Ownable(greatTimeLock_)
        nonZeroAddress(greatTimeLock_)
    {
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
        // TODO: emit
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
