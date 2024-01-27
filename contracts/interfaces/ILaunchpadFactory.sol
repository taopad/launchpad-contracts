// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface ILaunchpadFactory {
    function launchpads() external view returns (address[] memory);
    function trustedLaunchpads() external view returns (address[] memory);
    function protocolFeeAddress() external view returns (address);
    function protocolFee() external view returns (uint256);
}