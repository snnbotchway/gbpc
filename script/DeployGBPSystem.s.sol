// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {GBPCoin} from "src/GBPCoin.sol";
import {VaultMaster} from "src/VaultMaster.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployGBPSystem is Script {
    function run() external returns (GBPCoin gbpCoin, VaultMaster vaultMaster) {
        HelperConfig config = new HelperConfig();
        (uint256 deployerKey, address gbpUsdPriceFeed, uint8 gbpUsdPriceFeedDecimals) = config.activeNetworkConfig();

        address deployer = vm.createWallet(deployerKey).addr;

        vm.startBroadcast(deployerKey);
        gbpCoin = new GBPCoin(deployer);
        vaultMaster = new VaultMaster(makeAddr("temp dao addr"), address(gbpCoin), gbpUsdPriceFeed, gbpUsdPriceFeedDecimals);

        bytes32 adminRole = gbpCoin.DEFAULT_ADMIN_ROLE();
        bytes32 minterRole = gbpCoin.MINTER_ROLE();

        gbpCoin.grantRole(adminRole, address(vaultMaster));
        gbpCoin.grantRole(minterRole, address(vaultMaster)); // TODO: Vault Master should not be a minter
        gbpCoin.renounceRole(adminRole, deployer);
        vm.stopBroadcast();
    }
}
