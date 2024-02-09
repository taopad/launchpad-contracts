// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MainLaunchpadInfo} from "./ILaunchpadFactory.sol";

interface ILaunchpadDeployer {
    function deployLaunchpad(MainLaunchpadInfo memory _launchpadInfo, address _operator) external returns (address);
}