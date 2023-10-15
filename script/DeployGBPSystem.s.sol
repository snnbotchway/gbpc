// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {GBPCoin} from "src/GBPCoin.sol";

contract DeployGBPSystem is Script {
    function run() external returns (GBPCoin gbpCoin) {
        vm.startBroadcast();
        gbpCoin = new GBPCoin(msg.sender);
        // TODO gbpCoin.transferOwnership(vault);
        vm.stopBroadcast();
    }
}
