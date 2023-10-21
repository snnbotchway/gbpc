// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {GBPCoin} from "src/GBPCoin.sol";
import {GreatDAO} from "src/dao/GreatDAO.sol";
import {GreatCoin} from "src/dao/GreatCoin.sol";
import {GreatTimeLock} from "src/dao/GreatTimeLock.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VaultMaster} from "src/VaultMaster.sol";

contract DeployGBPSystem is Script {
    uint256 public constant MIN_DELAY = 1 days;
    address public constant TIMELOCK_ADMIN = address(0);
    address[] proposers;
    address[] executors;

    function run()
        external
        returns (
            GreatDAO greatDAO,
            GreatTimeLock timelock,
            VaultMaster vaultMaster,
            GBPCoin gbpCoin,
            GreatCoin greatCoin,
            HelperConfig config
        )
    {
        config = new HelperConfig();
        (uint256 deployerKey, address gbpUsdPriceFeed, uint8 gbpUsdPriceFeedDecimals,,,) = config.activeNetworkConfig();
        address deployer = vm.createWallet(deployerKey).addr;

        vm.startBroadcast(deployerKey);
        gbpCoin = new GBPCoin(deployer);
        greatCoin = new GreatCoin(deployer);
        timelock = new GreatTimeLock(MIN_DELAY, proposers, executors, TIMELOCK_ADMIN);
        greatDAO = new GreatDAO(greatCoin, timelock);
        vaultMaster = new VaultMaster(address(timelock), address(gbpCoin), gbpUsdPriceFeed, gbpUsdPriceFeedDecimals);

        bytes32 adminRole = gbpCoin.DEFAULT_ADMIN_ROLE();
        gbpCoin.grantRole(adminRole, address(vaultMaster));
        gbpCoin.renounceRole(adminRole, deployer);
        vm.stopBroadcast();
    }
}
