// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract HelperConfig is Script {
    error HC__NoConfigForCurrentChainId(uint256 currentChainId);

    struct NetworkConfig {
        uint256 deployerKey;
        address gbpUsdPriceFeed;
        uint8 gbpUsdPriceFeedDecimals;
    }

    int256 public constant GBP_USD_PRICE = 121560000;

    uint256 private constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = _getSepoliaConfig();
        } else if (block.chainid == 31337) {
            activeNetworkConfig = _getOrCreateAnvilConfig();
        }

        if (!_configExistsForCurrentChain()) revert HC__NoConfigForCurrentChainId(block.chainid);
    }

    function _getSepoliaConfig() private view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: vm.envUint("PRIVATE_KEY"),
            gbpUsdPriceFeed: 0x91FAB41F5f3bE955963a986366edAcff1aaeaa83,
            gbpUsdPriceFeedDecimals: 8
        });
    }

    function _getOrCreateAnvilConfig() private returns (NetworkConfig memory) {
        if (_configExistsForCurrentChain()) return activeNetworkConfig;

        vm.broadcast();
        MockV3Aggregator gbpUsdPriceFeed = new MockV3Aggregator(8, GBP_USD_PRICE);

        return NetworkConfig({
            deployerKey: DEFAULT_ANVIL_KEY,
            gbpUsdPriceFeed: address(gbpUsdPriceFeed),
            gbpUsdPriceFeedDecimals: 8
        });
    }

    function _configExistsForCurrentChain() private view returns (bool) {
        return activeNetworkConfig.deployerKey != 0;
    }
}
