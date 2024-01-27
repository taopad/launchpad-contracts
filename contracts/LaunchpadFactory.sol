// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Launchpad.sol";

contract LaunchpadFactory is Ownable(msg.sender) {

    event LaunchpadCreated(address indexed launchpad, address indexed token);
    event ProtocolFeeUpdated(address indexed protocolFeeAddress, uint256 newProtocolFee);
    event ProtocolFeeAddressUpdated(address protocolFeeAddress, address newProtocolFeeAddress);

    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _launchpads;

    address public protocolFeeAddress;
    uint256 public protocolFee;

    mapping(address => bool) public isTrusted;

    constructor(address _protocolFeeAddress, uint256 _protocolFee) {

        require(
            _protocolFeeAddress != address(0),
            "LaunchpadFactory: ZERO_PROTOCOL_FEE_ADDRESS"
        );

        require(
            _protocolFee > 0,
            "LaunchpadFactory: INVALID_PROTOCOL_FEE"
        );

        protocolFeeAddress = _protocolFeeAddress;

        // 10% MAX protocol fee
        require(_protocolFee <= 1000, "LaunchpadFactory: INVALID_PROTOCOL_FEE");

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

    function updateProtocolFee(uint256 _protocolFee) external onlyOwner {

        // 10% MAX protocol fee
        require(_protocolFee <= 1000, "LaunchpadFactory: INVALID_PROTOCOL_FEE");

        protocolFee = _protocolFee;
        emit ProtocolFeeUpdated(protocolFeeAddress, protocolFee);

    }

    function updateProtocolFeeAddress(address _protocolFeeAddress) external onlyOwner {
        require(
            _protocolFeeAddress != address(0),
            "LaunchpadFactory: ZERO_PROTOCOL_FEE_ADDRESS"
        );
        emit ProtocolFeeAddressUpdated(protocolFeeAddress, _protocolFeeAddress);
        protocolFeeAddress = _protocolFeeAddress;
    }

    function createLaunchpad(
        string memory _name,
        address _token,
        uint256 _ethPricePerToken,
        uint256 _minTokenBuy,
        uint256 _maxTokenBuy,
        uint256 _startDate,
        uint256 _endDate,
        uint256 _releaseDelay,
        uint256 _vestingDuration
    ) external returns (address) {

        Launchpad launchpad = new Launchpad(
            _name,
            _token,
            _ethPricePerToken,
            _minTokenBuy,
            _maxTokenBuy,
            _startDate,
            _endDate,
            protocolFee,
            protocolFeeAddress,
            _releaseDelay,
            _vestingDuration,
            msg.sender
        );

        _launchpads.add(address(launchpad));

        emit LaunchpadCreated(address(launchpad), _token);

        return address(launchpad);
    }


}
