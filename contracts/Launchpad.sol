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



contract Launchpad {
    using SafeERC20 for IERC20;
    
    event TokensPurchased(address indexed _token, address indexed buyer, uint256 amount);
    event TokensClaimed(address indexed _token, address indexed buyer, uint256 amount);
    event ethPricePerTokenUpdated(address indexed _token, uint256 newEthPricePerToken);
    event WhitelistUpdated(uint256 wlBlockNumber, uint256 wlMinBalance, bytes32 wlRoot);
    event TokenHardCapUpdated(address indexed _token, uint256 newTokenHardCap);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event VestingDurationUpdated(uint256 newVestingDuration);
    modifier onlyOperator() {
        if (msg.sender != operator) revert OperatorZeroAddress();
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
    uint256 public maxTokenBuy;

    uint256 public startDate;
    uint256 public endDate;

    uint256 public protocolFee;
    address public protocolFeeAddress;

    uint256 public releaseDelay;
    uint256 public vestingDuration;

    mapping (address => uint256) public purchasedAmount;
    mapping (address => uint256) public claimedAmount;
    uint256 public totalPurchasedAmount;

    uint256 public wlBlockNumber;
    uint256 public wlMinBalance;
    bytes32 public wlRoot;

    constructor(
        MainLaunchpadInfo memory _info,
        uint256 _protocolFee,
        address _protocolFeeAddress,
        address _operator,
        address _factory
    ) {

        name = _info.name;
        factory = _factory;

        if (_info.ethPricePerToken == 0) revert InvalidEthPrice();
        if (_info.minTokenBuy == 0) revert InvalidMinTokenBuy();
        if (_info.maxTokenBuy == 0) revert InvalidMaxTokenBuy();
        if (_info.startDate <= block.timestamp) revert InvalidStartDate();
        if (_info.endDate <= _info.startDate) revert InvalidEndDate();
        if (_operator == address(0)) revert ZeroAddress();

        operator = _operator;

        token = IERC20(_info.token);
        decimals = IERC20Metadata(_info.token).decimals();
        tokenUnit = 10**decimals;

        ethPricePerToken = _info.ethPricePerToken;
        minTokenBuy = _info.minTokenBuy;
        maxTokenBuy = _info.maxTokenBuy;

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
        return block.timestamp >= startDate;
    }

    /**
     * @return true if the launchpad has ended
     */

    function isEnded() public view returns (bool) {
        return block.timestamp >= endDate;
    }

    /**
     * @return true if the tokens in the launchpad are claimable
     */

    function isClaimable() public view returns (bool) {
        return block.timestamp >= endDate + releaseDelay;
    }

    /**
     * 
     * @param newOperator new operator address
     * This function is used to transfer ownership of the launchpad to another address.
     */

    function transferOperatorOwnership(address newOperator) external onlyOperator {
        if (newOperator == address(0)) revert ZeroAddress();
        if (newOperator == operator) revert SameOperator();

        emit OperatorTransferred(operator, newOperator);
        operator = newOperator;
    }

    /**
     * @param _wlBlockNumber block number of the whitelist's snapshot
     * @param _wlMinBalance min balance threshold of the whitelist
     * @param _wlMinBalance merkle tree root of the whitelist
     *
     * When set, the buyTokens() will require a proof matching the buyer address and this root.
     */
    function updateWhitelist(uint256 _wlBlockNumber, uint256 _wlMinBalance, bytes32 _wlRoot) external onlyOperator {
        wlBlockNumber = _wlBlockNumber;
        wlMinBalance = _wlMinBalance;
        wlRoot = _wlRoot;

        emit WhitelistUpdated(wlBlockNumber, wlMinBalance, wlRoot);
    }

    /**
     * 
     * @param _tokenHardCapIncrement amount of tokens to increase the hard cap by
     * This function is used to increase the hard cap of the launchpad.
     * The operator can increase the hard cap by any amount of tokens.
     */

    function increaseHardCap(uint256 _tokenHardCapIncrement) external onlyOperator {
        if (_tokenHardCapIncrement == 0) revert InvalidTokenHardCapIncrement();

        uint256 _feeAmount = _tokenHardCapIncrement * protocolFee / 10000;
        if (_feeAmount > 0) {
            token.safeTransferFrom(msg.sender, protocolFeeAddress, _feeAmount);
            _tokenHardCapIncrement -= _feeAmount;
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), _tokenHardCapIncrement);
        tokenHardCap += _tokenHardCapIncrement;
        emit TokenHardCapUpdated(address(token), tokenHardCap);
    }

    /**
     * 
     * @param _ethPricePerToken new ETH price per token
     * This function is used to change the ETH price per token.
     */

    function updateEthPricePerToken(uint256 _ethPricePerToken) external onlyOperator {
        if (_ethPricePerToken == 0) revert InvalidEthPrice();
        emit ethPricePerTokenUpdated(address(token), _ethPricePerToken);
        ethPricePerToken = _ethPricePerToken;
    }

    /**
     * 
     * @param ethAmount amount of ETH
     * @return the amount of tokens that the user will receive for the given amount of ETH
     * This function is used to calculate the amount of tokens that the user will receive for the given amount of ETH.
     */

    function ethToToken(uint256 ethAmount) public view returns (uint256) {
        return ethAmount * tokenUnit / ethPricePerToken;
    }

    /**
     * @param proof the proof in case this launchpad has a whitelist, empty otherwise.
     * Allows the user to buy tokens during the launchpad.
     */
    function buyTokens(bytes32[] calldata proof) external payable {
        if (!isStarted()) revert NotStarted();
        if (isEnded()) revert Ended();
        if (msg.value == 0) revert InvalidBuyAmount();


        // check proof validity when a whitelist has been set.
        if (wlBlockNumber > 0 && !MerkleProof.verifyCalldata(
            proof, wlRoot, keccak256(bytes.concat(keccak256(abi.encode(msg.sender))))
        )) {
            revert InvalidWhitelistProof();
        }

        uint256 _tokensAmount = ethToToken(msg.value);
        if (_tokensAmount < minTokenBuy) {
            revert AmountTooLow();
        }

        if (purchasedAmount[msg.sender] + _tokensAmount > maxTokenBuy) {
            revert AmountExceedsMaxTokenAmount();
        }

        if (totalPurchasedAmount + _tokensAmount > tokenHardCap) {
            revert AmountExceedsHardCap();
        }

        purchasedAmount[msg.sender] += _tokensAmount;
        totalPurchasedAmount += _tokensAmount;

        emit TokensPurchased(address(token), msg.sender, _tokensAmount);
    }

    /**
     * 
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
     * Allows the user to claim their tokens after the launchpad has ended.
     * The tokens are released linearly over the vesting duration.
     */

    function claimTokens() external {
        if (!isClaimable()) {
            revert NotClaimable();
        }
        if (purchasedAmount[msg.sender] == 0) {
            revert NoPurchasedTokens();
        }

        uint256 _claimableAmount = claimableAmount(msg.sender);
        if (_claimableAmount == 0) {
            revert NoClaimableTokens();
        }
        claimedAmount[msg.sender] += _claimableAmount;

        token.safeTransfer(msg.sender, _claimableAmount);

        emit TokensClaimed(address(token), msg.sender, _claimableAmount);
    }

    /**
     * Allows the operator to withdraw ETH after the launchpad has ended.
     */

    function withdrawEth() external onlyOperator {
        if (!isEnded()) {
            revert NotEnded();
        }
        uint256 _balance = address(this).balance;
        if (_balance == 0) {
            revert NoBalanceToWithdraw();
        }
        (bool success, ) = payable(msg.sender).call{value: _balance}("");
        if (!success) {
            revert EthereumTransferFailed();
        }
    }

    /**
     * Allows the operator to withdraw any remaining tokens after the launchpad has ended.
     * This is useful in case the launchpad has not sold all the tokens.
     */

    function withdrawTokens() external onlyOperator {
        if (!isEnded()) {
            revert NotEnded();
        }
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

    /**
     * 
     * @param _vestingDuration new vesting duration
     * This function is used to change the vesting duration of the launchpad.
     */

    function setVestingDuration(uint256 _vestingDuration) external onlyOperator {
        require(!isEnded(), "Launchpad: ENDED");
        emit VestingDurationUpdated(_vestingDuration);
        vestingDuration = _vestingDuration;
    }

    /**
     * 
     * @param _name new name of the launchpad
     * This function is used to change the name of the launchpad.
     */

    function setName(string memory _name) external onlyOperator {
        name = _name;
    }

    /**
     * 
     * @param _newOwner new owner address
     * This function is used to transfer ownership of purchased tokens to another address.
     * This is useful for external integrators suchs as Zappers,
     * which need to transfer ownership of purchased tokens to the user.
     */

    function transferPurchasedOwnership(address _newOwner) external {

        if (isEnded()) {
            revert Ended();
        }

        uint256 _purchasedAmount = purchasedAmount[msg.sender];
        uint256 _newUserPurchaseAmount = purchasedAmount[_newOwner];

        if (_newUserPurchaseAmount + _purchasedAmount > maxTokenBuy) {
            revert AmountExceedsMaxTokenAmount();
        }

        purchasedAmount[msg.sender] = 0;
        purchasedAmount[_newOwner] += _purchasedAmount;
    }
}

