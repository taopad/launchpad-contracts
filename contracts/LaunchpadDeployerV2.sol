// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MainLaunchpadInfo} from "./interfaces/ILaunchpadFactory.sol";
import {LaunchpadV2} from "./LaunchpadV2.sol";
import {ILaunchpadFactory} from "./interfaces/ILaunchpadFactory.sol";

contract LaunchpadDeployerV2 {
    function deployLaunchpad(
        MainLaunchpadInfo memory _launchpadInfo, 
        address _operator
    ) 
        external 
        returns (address) 
    {
        ILaunchpadFactory _factory = ILaunchpadFactory(msg.sender);

        return address(
            new LaunchpadV2(
                _launchpadInfo, 
                _factory.protocolFee(), 
                _factory.protocolFeeAddress(), 
                _operator, 
                msg.sender
            )
        );
    }
}
