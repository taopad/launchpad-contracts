// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Launchpad.sol";
import "./constants/Errors.sol";

import {ILaunchpadDeployer} from "./interfaces/ILaunchpadDeployer.sol";
import {MainLaunchpadInfo} from "./interfaces/ILaunchpadFactory.sol";

contract LaunchpadFactory is Ownable(msg.sender) {

    event LaunchpadCreated(address indexed launchpad, address indexed token);
    event ProtocolFeeUpdated(address indexed protocolFeeAddress, uint256 newProtocolFee);
    event ProtocolFeeAddressUpdated(address oldProtocolFeeAddress, address newProtocolFeeAddress);
    event DeployerUpdated(address oldDeployer, address newDeployer);

    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _launchpads;

    address public protocolFeeAddress;
    uint256 public protocolFee;

    mapping(address => bool) public isTrusted;

    ILaunchpadDeployer public deployer;

    constructor(address _protocolFeeAddress, uint256 _protocolFee, address _deployer) {

        if (_deployer == address(0) || _protocolFeeAddress == address(0)) revert ZeroAddress();
        
        if (_protocolFee > 1000) {
            revert InvalidProtocolFee();
        }

        protocolFeeAddress = _protocolFeeAddress;
        deployer = ILaunchpadDeployer(_deployer);
        protocolFee = _protocolFee;

    }

    function launchpads() external view returns (address[] memory) {
        uint256 length = _launchpads.length();
        address[] memory launchpads_ = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            launchpads_[i] = _launchpads.at(i);
        }
        return launchpads_;
    }

    function trustedLaunchpads() external view returns (address[] memory) {
        uint256 length = _launchpads.length();
        address[] memory launchpads_ = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            if (isTrusted[_launchpads.at(i)]) {
                launchpads_[i] = _launchpads.at(i);
            }
        }
        return launchpads_;
    }

    function launchpadsLength() external view returns (uint256) {
        return _launchpads.length();
    }

    function launchpadAtIndex(uint256 index) external view returns (address) {
        return _launchpads.at(index);
    }

    function addTrusted(address _address) external onlyOwner {
        isTrusted[_address] = true;
    }

    function removeTrusted(address _address) external onlyOwner {
        isTrusted[_address] = false;
    }

    function setDeployer(address _deployer) external onlyOwner {
        deployer = ILaunchpadDeployer(_deployer);
    }

    function updateProtocolFee(uint256 _protocolFee) external onlyOwner {

        if (_protocolFee > 1000) {
            revert InvalidProtocolFee();
        }

        protocolFee = _protocolFee;
        emit ProtocolFeeUpdated(protocolFeeAddress, protocolFee);

    }

    function updateProtocolFeeAddress(address _protocolFeeAddress) external onlyOwner {
        if (_protocolFeeAddress == address(0))
            revert ZeroAddress();

        emit ProtocolFeeAddressUpdated(protocolFeeAddress, _protocolFeeAddress);
        protocolFeeAddress = _protocolFeeAddress;
    }

    function createLaunchpad(
        MainLaunchpadInfo memory _mainLaunchpadInfo
    ) external returns (address) {

        address _launchpad = deployer.deployLaunchpad(_mainLaunchpadInfo, msg.sender);

        require(_launchpads.add(_launchpad));

        emit LaunchpadCreated(address(_launchpad), _mainLaunchpadInfo.token);

        return address(_launchpad);
    }

}
