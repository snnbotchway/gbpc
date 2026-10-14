// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {USDPriceFeed} from "./Structs.sol";

library OracleLib {
    error InvalidPriceFeed(address feed);
    error InvalidPrice(address feed, int256 answer);
    error StalePrice(address feed, uint256 updatedAt);

    uint8 internal constant PRICE_DECIMALS = 18;

    function validate(USDPriceFeed memory priceFeed) internal view {
        if (
            priceFeed.feed == address(0) || priceFeed.maxAge == 0 || priceFeed.decimals > PRICE_DECIMALS
                || AggregatorV3Interface(priceFeed.feed).decimals() != priceFeed.decimals
        ) revert InvalidPriceFeed(priceFeed.feed);
    }

    function price(USDPriceFeed memory priceFeed) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(priceFeed.feed).latestRoundData();
        if (answer <= 0) revert InvalidPrice(priceFeed.feed, answer);
        if (updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > priceFeed.maxAge) {
            revert StalePrice(priceFeed.feed, updatedAt);
        }
        return uint256(answer) * 10 ** (PRICE_DECIMALS - priceFeed.decimals);
    }
}
