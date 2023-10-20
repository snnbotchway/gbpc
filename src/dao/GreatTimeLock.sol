// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.21;

import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

contract GreatTimeLock is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
