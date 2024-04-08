// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/ILaunchpadFactory.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {MainLaunchpadInfo} from "./interfaces/ILaunchpadFactory.sol";
import "./constants/Errors.sol";

contract LaunchpadV2 {
    using SafeERC20 for IERC20;

    event NameUpdated(string newName);
    event RootUpdated(bytes32 newRoot);
    event DatesUpdated(uint256 newStartDate, uint256 newEndDate);
    event TokensClaimed(address indexed _token, address indexed buyer, uint256 amount);
    event TokensPurchased(address indexed _token, address indexed buyer, uint256 amount);
    event TokenHardCapUpdated(address indexed _token, uint256 newTokenHardCap);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event ReleaseDelayUpdated(uint256 newReleaseDelay);
    event VestingDurationUpdated(uint256 newVestingDuration);
    event EthPricePerTokenUpdated(address indexed _token, uint256 newEthPricePerToken);

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    address public operator;
    string public name;

    IERC20 public immutable token;
    uint256 public immutable decimals;
    uint256 public immutable tokenUnit;

    address public immutable factory;

    uint256 public ethPricePerToken;
    uint256 public tokenHardCap;

    uint256 public minTokenBuy;

    uint256 public startDate;
    uint256 public endDate;

    uint256 public protocolFee;
    address public protocolFeeAddress;

    uint256 public releaseDelay;
    uint256 public vestingDuration;

    mapping(address => uint256) public purchasedAmount;
    mapping(address => uint256) public claimedAmount;
    uint256 public totalPurchasedAmount;

    bytes32 public root;

    bool public isRootSet;
    bool public isValidated; // launchpad parameters must be validated after deployment.

    constructor(
        MainLaunchpadInfo memory _info,
        uint256 _protocolFee,
        address _protocolFeeAddress,
        address _operator,
        address _factory
    ) {
        name = _info.name;
        factory = _factory;

        // remaining check are done in the validate function now.

        if (_operator == address(0)) revert ZeroAddress();
        if (_info.minTokenBuy == 0) revert InvalidMinTokenBuy();

        if (_info.startDate > 0) {
            if (_info.startDate <= block.timestamp) revert InvalidStartDate();
            if (_info.endDate <= _info.startDate) revert InvalidEndDate();
        }

        operator = _operator;

        token = IERC20(_info.token);
        decimals = IERC20Metadata(_info.token).decimals();
        tokenUnit = 10 ** decimals;

        ethPricePerToken = _info.ethPricePerToken;
        minTokenBuy = _info.minTokenBuy == 0 ? tokenUnit : _info.minTokenBuy;
        // maxTokenBuy = _info.maxTokenBuy; // no more global max buy

        startDate = _info.startDate;
        endDate = _info.endDate;

        protocolFee = _protocolFee;
        protocolFeeAddress = _protocolFeeAddress;

        releaseDelay = _info.releaseDelay;
        vestingDuration = _info.vestingDuration;
    }

    /**
     * @return true if the launchpad has started
     */
    function isStarted() public view returns (bool) {
        return isValidated && block.timestamp >= startDate;
    }

    /**
     * @return true if the launchpad has ended
     */
    function isEnded() public view returns (bool) {
        return isValidated && block.timestamp >= endDate;
    }

    /**
     * @return true if the tokens in the launchpad are claimable
     */
    function isClaimable() public view returns (bool) {
        return isValidated && block.timestamp >= endDate + releaseDelay;
    }

    /**
     * @param _operator new operator address
     * This function is used to transfer ownership of the launchpad to another address.
     */
    function transferOperatorOwnership(address _operator) external onlyOperator {
        if (_operator == address(0)) revert ZeroAddress();
        if (_operator == operator) revert SameOperator();

        emit OperatorTransferred(operator, _operator);
        operator = _operator;
    }

    /**
     * @param _name new name of the launchpad
     * This function is used to change the name of the launchpad.
     */
    function updateName(string memory _name) external onlyOperator {
        emit NameUpdated(_name);
        name = _name;
    }

    /**
     * @param _startDate new start date
     * @param _endDate new end date
     * This function is used to change the start and end dates of the launchpad.
     * Can't update anymore once it has been validated.
     */
    function updateDates(uint256 _startDate, uint256 _endDate) public onlyOperator {
        if (isValidated) revert AlreadyValidated();
        if (_endDate <= _startDate) revert InvalidEndDate();
        if (_startDate <= block.timestamp) revert InvalidStartDate();
        emit DatesUpdated(_startDate, _endDate);
        startDate = _startDate;
        endDate = _endDate;
    }

    /**
     * @param _startDate new start date
     * @param _duration duration of the launchpad
     * This function is an helper function to change start and end dates of the launchpad.
     */
    function updateStartDateAndDuration(uint256 _startDate, uint256 _duration) external onlyOperator {
        updateDates(_startDate, _startDate + _duration);
    }

    /**
     * @param _ethPricePerToken new ETH price per token
     * This function is used to change the ETH price per token.
     */
    function updateEthPricePerToken(uint256 _ethPricePerToken) external onlyOperator {
        if (_ethPricePerToken == 0) revert InvalidEthPrice();
        emit EthPricePerTokenUpdated(address(token), _ethPricePerToken);
        ethPricePerToken = _ethPricePerToken;
    }

    /**
     * @param _root new root of the allocation merkle tree.
     * This function is used to update the allocation merkle tree root.
     */
    function updateRoot(bytes32 _root) external onlyOperator {
        emit RootUpdated(_root);
        isRootSet = true;
        root = _root;
    }

    /**
     * @param _releaseDelay new release delay
     * This function is used to change the release delay of the launchpad.
     * Can't update anymore once the launchpad ended.
     */
    function updateReleaseDelay(uint256 _releaseDelay) external onlyOperator {
        if (isEnded()) revert Ended();
        emit ReleaseDelayUpdated(_releaseDelay);
        releaseDelay = _releaseDelay;
    }

    /**
     * @param _vestingDuration new vesting duration
     * This function is used to change the vesting duration of the launchpad.
     * Can't update anymore once the launchpad ended.
     */
    function updateVestingDuration(uint256 _vestingDuration) external onlyOperator {
        if (isEnded()) revert Ended();
        emit VestingDurationUpdated(_vestingDuration);
        vestingDuration = _vestingDuration;
    }

    /**
     * @param _tokenHardCapIncrement amount of tokens to increase the hard cap by
     * This function is used to increase the hard cap of the launchpad.
     * The operator can increase the hard cap by any amount of tokens.
     */
    function increaseHardCap(uint256 _tokenHardCapIncrement) external onlyOperator {
        if (_tokenHardCapIncrement == 0) revert InvalidTokenHardCapIncrement();
        emit TokenHardCapUpdated(address(token), tokenHardCap);
        IERC20(token).safeTransferFrom(msg.sender, address(this), _tokenHardCapIncrement);
        tokenHardCap += _tokenHardCapIncrement;
    }

    /**
     * Validate the launchpad configuration so it can actually start with the current parameters.
     */
    function validate() external onlyOperator {
        if (isValidated) revert AlreadyValidated();
        if (tokenHardCap == 0) revert InvalidHardCap();
        if (ethPricePerToken == 0) revert InvalidEthPrice();
        if (startDate == 0) revert InvalidStartDate();
        if (block.timestamp >= endDate) revert InvalidEndDate();
        if (!isRootSet) revert RootNotSet();

        uint256 _tokenBalance = token.balanceOf(address(this));

        if (_tokenBalance < tokenHardCap) {
            revert InvalidTokenBalance();
        }

        isValidated = true;
    }

    /**
     * @param _ethAmount amount of ETH
     * @return the amount of tokens that the user will receive for the given amount of ETH
     * This function is used to calculate the amount of tokens that the user will receive for the given amount of ETH.
     */
    function ethToToken(uint256 _ethAmount) public view returns (uint256) {
        return _ethAmount * tokenUnit / ethPricePerToken;
    }

    /**
     * @param _address the address of the buyer
     * @param _maxTokenBuy the maximum amount of tokens the buyer can purchase
     * @param _proof the proof matching the (addr, maxTokenBuy, root) combination
     * Allows the user to buy tokens during the launchpad. Anyone can buy for another address as long
     * as the matching proof is provided. Usefull for external integrators like Zappers.
     */
    function buyTokens(address _address, uint256 _maxTokenBuy, bytes32[] calldata _proof) external payable {
        if (isEnded()) revert Ended();
        if (!isStarted()) revert NotStarted();
        if (msg.value == 0) revert InvalidBuyAmount();

        uint256 _tokensAmount = ethToToken(msg.value);

        bool _verifiction = MerkleProof.verifyCalldata(
            _proof, root, keccak256(bytes.concat(keccak256(abi.encode(_address, _maxTokenBuy))))
        );

        if (!_verifiction) {
            revert InvalidProof();
        }

        if (_tokensAmount < minTokenBuy) {
            revert AmountTooLow();
        }

        if (purchasedAmount[_address] + _tokensAmount > _maxTokenBuy) {
            revert AmountExceedsMaxTokenAmount();
        }

        if (totalPurchasedAmount + _tokensAmount > tokenHardCap) {
            revert AmountExceedsHardCap();
        }

        purchasedAmount[_address] += _tokensAmount;
        totalPurchasedAmount += _tokensAmount;

        emit TokensPurchased(address(token), _address, _tokensAmount);
    }

    /**
     * @param _address address of the user
     * @return the amount of tokens that the user can claim
     * This function is used to calculate the amount of tokens that the user can claim.
     * The tokens are released linearly over the vesting duration.
     */
    function claimableAmount(address _address) public view returns (uint256) {
        if (!isClaimable()) {
            return 0;
        }

        uint256 _purchasedAmount = purchasedAmount[_address];
        uint256 _claimedAmount = claimedAmount[_address];
        uint256 _netAmount = _purchasedAmount - _claimedAmount;

        if (vestingDuration == 0 || (block.timestamp >= endDate + releaseDelay + vestingDuration)) {
            return _netAmount;
        }

        uint256 _unlockedAmount = _purchasedAmount * (block.timestamp - endDate - releaseDelay) / vestingDuration;

        if (_unlockedAmount > _purchasedAmount) {
            _unlockedAmount = _purchasedAmount;
        }

        _unlockedAmount -= _claimedAmount;

        return _unlockedAmount;
    }

    /**
     * @param _address address of the user
     * Allows the user to claim their tokens after the launchpad has ended.
     * The tokens are released linearly over the vesting duration.
     */
    function claimTokens(address _address) external {
        if (!isClaimable()) {
            revert NotClaimable();
        }

        if (purchasedAmount[_address] == 0) {
            revert NoPurchasedTokens();
        }

        uint256 _claimableAmount = claimableAmount(_address);

        if (_claimableAmount == 0) {
            revert NoClaimableTokens();
        }

        claimedAmount[_address] += _claimableAmount;

        token.safeTransfer(_address, _claimableAmount);

        emit TokensClaimed(address(token), _address, _claimableAmount);
    }

    /**
     * Allows the operator to withdraw ETH after the launchpad has ended.
     * Protocol fee are taked here.
     */
    function withdrawEth() external onlyOperator {
        if (!isEnded()) revert NotEnded();

        uint256 _balance = address(this).balance;
        uint256 _feeAmount = _balance * protocolFee / 10000;
        uint256 _actualEthAmount = _balance - _feeAmount;

        if (_actualEthAmount == 0) {
            revert NoBalanceToWithdraw();
        }

        if (_feeAmount > 0) {
            (bool success1,) = payable(protocolFeeAddress).call{value: _feeAmount}("");

            if (!success1) {
                revert EthereumFeeTransferFailed();
            }
        }

        (bool success2,) = payable(msg.sender).call{value: _actualEthAmount}("");

        if (!success2) {
            revert EthereumTransferFailed();
        }
    }

    /**
     * Allows the operator to withdraw any remaining tokens after the launchpad has ended.
     * This is useful in case the launchpad has not sold all the tokens.
     */
    function withdrawTokens() external onlyOperator {
        if (!isEnded()) revert NotEnded();

        uint256 _balance = token.balanceOf(address(this));
        uint256 _purchasedAmount = totalPurchasedAmount;

        if (_purchasedAmount > _balance) {
            _balance = 0;
        } else {
            _balance -= _purchasedAmount;
        }

        if (_balance <= 0) {
            revert NoBalanceToWithdraw();
        }

        token.safeTransfer(msg.sender, _balance);
    }
}
