// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";

import {DeployGBPCSystem} from "script/DeployGBPCSystem.s.sol";
import {GBPCoin} from "src/GBPCoin.sol";
import {GreatDAO} from "src/dao/GreatDAO.sol";
import {GreatCoin} from "src/dao/GreatCoin.sol";
import {GreatTimeLock} from "src/dao/GreatTimeLock.sol";
import {GreatVault} from "src/GreatVault.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VaultMaster} from "src/VaultMaster.sol";
import {USDPriceFeed} from "src/utils/Structs.sol";

contract TestGreatDAO is Test {
    GBPCoin public gbpCoin;
    GreatCoin public greatCoin;
    GreatDAO public greatDAO;
    GreatTimeLock public timelock;
    HelperConfig public config;
    VaultMaster public vaultMaster;

    address public wEth;
    address public wEthUsdPriceFeed;
    uint8 public wEthUsdPriceFeedDecimals;

    uint8 public constant LIQUIDATION_THRESHOLD = 80;
    uint8 public constant LIQUIDATION_SPREAD = 10;
    uint8 public constant CLOSE_FACTOR = 50;

    address public USER = makeAddr("user");

    address[] public targets;
    uint256[] public values;
    bytes[] public calldatas;

    function setUp() public {
        DeployGBPCSystem gbpcDeployer = new DeployGBPCSystem();
        (greatDAO, timelock, vaultMaster, gbpCoin, greatCoin, config) = gbpcDeployer.run();

        uint256 deployerKey;
        (deployerKey,,, wEth, wEthUsdPriceFeed, wEthUsdPriceFeedDecimals) = config.activeNetworkConfig();
        address deployer = vm.createWallet(deployerKey).addr;

        vm.prank(deployer);
        greatCoin.delegate(USER);
    }

    function testTimeLockOwnsTheVaultMaster() public {
        assertEq(address(timelock), vaultMaster.owner());
    }

    function testDeployVaultGovernance() public {
        string memory description = "Deploy WETH collateral vault.";
        bytes memory deployVaultCalldata = abi.encodeWithSignature(
            "deployVault(address,address,uint8,uint8,uint8,uint8)",
            wEth,
            wEthUsdPriceFeed,
            wEthUsdPriceFeedDecimals,
            LIQUIDATION_THRESHOLD,
            LIQUIDATION_SPREAD,
            CLOSE_FACTOR
        );

        targets.push(address(vaultMaster));
        values.push(0);
        calldatas.push(deployVaultCalldata);

        uint256 proposalId = greatDAO.propose(targets, values, calldatas, description);
        console2.log(uint256(greatDAO.state(proposalId)), "Proposal State after calling propose()");

        vm.warp(block.number + greatDAO.votingDelay() + 1);
        vm.roll(block.number + greatDAO.votingDelay() + 1);
        console2.log(uint256(greatDAO.state(proposalId)), "Proposal State after waiting for votingDelay");

        uint8 support = uint8(GovernorCountingSimple.VoteType.For);
        vm.prank(USER);
        greatDAO.castVote(proposalId, support);

        vm.warp(block.number + greatDAO.votingPeriod() + 1);
        vm.roll(block.number + greatDAO.votingPeriod() + 1);
        console2.log(uint256(greatDAO.state(proposalId)), "Proposal State after voting period");

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        greatDAO.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.number + timelock.getMinDelay() + 1);
        vm.roll(block.number + timelock.getMinDelay() + 1);
        console2.log(uint256(greatDAO.state(proposalId)), "Proposal State after queueing and waiting for timelock minDelay");

        address initialVault = vaultMaster.collateralVault(wEth);

        greatDAO.execute(targets, values, calldatas, descriptionHash);
        console2.log(uint256(greatDAO.state(proposalId)), "Proposal State after executing");

        address finalVault = vaultMaster.collateralVault(wEth);

        assertEq(initialVault, address(0));
        assertNotEq(finalVault, address(0));
        assertEq(GreatVault(finalVault).owner(), address(timelock));
        assertTrue(gbpCoin.hasRole(gbpCoin.MINTER_ROLE(), finalVault));
    }
}
