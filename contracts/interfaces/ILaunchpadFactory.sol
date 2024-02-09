// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


struct MainLaunchpadInfo {
    string name;
    address token;
    uint256 ethPricePerToken;
    uint256 minTokenBuy;
    uint256 maxTokenBuy;
    uint256 startDate;
    uint256 endDate;
    uint256 releaseDelay;
    uint256 vestingDuration;
}

interface ILaunchpadFactory {
    function launchpads() external view returns (address[] memory);
    function trustedLaunchpads() external view returns (address[] memory);
    function protocolFeeAddress() external view returns (address);
    function protocolFee() external view returns (uint256);
}