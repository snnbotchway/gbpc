// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {GBPCoin} from "src/GBPCoin.sol";
import {VaultMaster} from "src/VaultMaster.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployGBPSystem is Script {
    function run() external returns (GBPCoin gbpCoin, VaultMaster vaultMaster) {
        HelperConfig config = new HelperConfig();
        (uint256 deployerKey) = config.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        gbpCoin = new GBPCoin(msg.sender);
        vaultMaster = new VaultMaster(makeAddr("temp dao addr"), address(gbpCoin));

        bytes32 adminRole = gbpCoin.DEFAULT_ADMIN_ROLE();
        gbpCoin.grantRole(adminRole, address(vaultMaster));
        gbpCoin.renounceRole(adminRole, msg.sender);
        vm.stopBroadcast();
    }
}
