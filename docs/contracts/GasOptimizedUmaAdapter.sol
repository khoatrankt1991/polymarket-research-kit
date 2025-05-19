// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Auth } from "./mixins/Auth.sol";
import { BulletinBoard } from "./mixins/BulletinBoard.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { PayoutHelperLib } from "./libraries/PayoutHelperLib.sol";
import { IFinder } from "./interfaces/IFinder.sol";
import { IAddressWhitelist } from "./interfaces/IAddressWhitelist.sol";
import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { IOptimisticOracleV2 } from "./interfaces/IOptimisticOracleV2.sol";
import { IOptimisticRequester } from "./interfaces/IOptimisticRequester.sol";
import { IUmaCtfAdapter } from "./interfaces/IUmaCtfAdapter.sol";

/// @title GasOptimizedUmaAdapter
/// @notice Gas-optimized version of UMA CTF Adapter for Polymarket
contract GasOptimizedUmaAdapter is Auth, BulletinBoard, IOptimisticRequester, IUmaCtfAdapter {
    /*///////////////////////////////////////////////////////////////////
                            STORAGE OPTIMIZATIONS
    //////////////////////////////////////////////////////////////////*/
    
    // Bit flags for boolean fields (packed into a single uint8)
    uint8 constant FLAG_RESOLVED = 1;       // 0000 0001
    uint8 constant FLAG_PAUSED = 2;         // 0000 0010
    uint8 constant FLAG_RESET = 4;          // 0000 0100
    uint8 constant FLAG_REFUND = 8;         // 0000 1000
    uint8 constant FLAG_FLAGGED = 16;       // 0001 0000
    
    // Optimized storage structure
    struct OptimizedQuestionData {
        bytes32 ancillaryDataHash;           // Hash of data, not full data
        uint48 requestTimestamp;             // Reduced from uint256
        uint48 emergencyResolutionTimestamp; // Reduced from uint256
        address rewardToken;
        address creator;
        uint128 reward;                      // Reduced from uint256
        uint64 proposalBond;                 // Reduced from uint256
        uint32 liveness;                     // Reduced from uint256
        uint8 flags;                         // Packed boolean flags
    }
    
    /*///////////////////////////////////////////////////////////////////
                            IMMUTABLES & CONSTANTS
    //////////////////////////////////////////////////////////////////*/
    
    /// @notice Conditional Tokens Framework
    IConditionalTokens public immutable ctf;

    /// @notice Optimistic Oracle
    IOptimisticOracleV2 public immutable optimisticOracle;

    /// @notice Collateral Whitelist
    IAddressWhitelist public immutable collateralWhitelist;

    /// @notice Time period after which an admin can emergency resolve a condition
    uint256 public constant EMERGENCY_SAFETY_PERIOD = 2 days;

    /// @notice Unique query identifier for the Optimistic Oracle
    bytes32 public constant YES_OR_NO_IDENTIFIER = "YES_OR_NO_QUERY";

    /// @notice Maximum ancillary data length
    uint256 public constant MAX_ANCILLARY_DATA = 8139;
    
    /*///////////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////////*/
    
    // Main question data storage (optimized)
    mapping(bytes32 => OptimizedQuestionData) public questions;
    
    // Mapping from questionID to ancillary data (only stored for active questions)
    mapping(bytes32 => bytes) public questionAncillaryData;
    
    // Cache for resolved payouts to avoid recomputation
    mapping(bytes32 => uint256[]) public resolvedPayouts;
    
    /*///////////////////////////////////////////////////////////////////
                            CONSTRUCTOR & MODIFIERS
    //////////////////////////////////////////////////////////////////*/
    
    modifier onlyOptimisticOracle() {
        if (msg.sender != address(optimisticOracle)) revert NotOptimisticOracle();
        _;
    }
    
    /// @param _ctf     - The Conditional Token Framework Address
    /// @param _finder  - The UMA Finder contract address
    constructor(address _ctf, address _finder) {
        ctf = IConditionalTokens(_ctf);
        IFinder finder = IFinder(_finder);
        optimisticOracle = IOptimisticOracleV2(finder.getImplementationAddress("OptimisticOracleV2"));
        collateralWhitelist = IAddressWhitelist(finder.getImplementationAddress("CollateralWhitelist"));
    }
    
    /*///////////////////////////////////////////////////////////////////
                        OPTIMIZED PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////////*/
    
    /// @notice Initializes a question with gas-optimized storage
    /// @param ancillaryData - Data used to resolve a question
    /// @param rewardToken - ERC20 token for rewards and fees
    /// @param reward - Reward for OO proposers
    /// @param proposalBond - Bond required for OO proposers/disputers
    /// @param liveness - OO liveness period in seconds
    function initialize(
        bytes calldata ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        uint256 liveness
    ) external override returns (bytes32 questionID) {
        // Validate token is on whitelist
        if (!collateralWhitelist.isOnWhitelist(rewardToken)) revert UnsupportedToken();
        
        // Validate and append sender to ancillary data
        bytes memory data = abi.encodePacked(ancillaryData, msg.sender);
        if (ancillaryData.length == 0 || data.length > MAX_ANCILLARY_DATA) revert InvalidAncillaryData();
        
        // Generate questionID from data hash
        questionID = keccak256(data);
        
        // Check question not already initialized
        if (_isInitialized(questionID)) revert Initialized();
        
        uint256 timestamp = block.timestamp;
        
        // Store question data in optimized format
        questions[questionID] = OptimizedQuestionData({
            ancillaryDataHash: keccak256(data),
            requestTimestamp: uint48(timestamp),
            emergencyResolutionTimestamp: 0,
            rewardToken: rewardToken,
            creator: msg.sender,
            reward: uint128(reward),
            proposalBond: uint64(proposalBond),
            liveness: uint32(liveness),
            flags: 0
        });
        
        // Store full ancillary data (needed for OO interaction)
        questionAncillaryData[questionID] = data;
        
        // Prepare condition on CTF
        ctf.prepareCondition(address(this), questionID, 2);
        
        // Request price from OO
        _requestPrice(msg.sender, timestamp, data, rewardToken, reward, proposalBond, liveness);
        
        emit QuestionInitialized(questionID, timestamp, msg.sender, data, rewardToken, reward, proposalBond);
        
        return questionID;
    }
    
    /// @notice Batch initialize multiple questions at once
    /// @param ancillaryDatas - Array of ancillary data
    /// @param rewardTokens - Array of reward tokens
    /// @param rewards - Array of rewards
    /// @param proposalBonds - Array of proposal bonds
    /// @param livenesses - Array of liveness periods
    function batchInitialize(
        bytes[] calldata ancillaryDatas,
        address[] calldata rewardTokens,
        uint256[] calldata rewards,
        uint256[] calldata proposalBonds,
        uint256[] calldata livenesses
    ) external returns (bytes32[] memory questionIDs) {
        uint256 length = ancillaryDatas.length;
        
        // Validate array lengths match
        if (
            rewardTokens.length != length ||
            rewards.length != length ||
            proposalBonds.length != length ||
            livenesses.length != length
        ) revert ArrayLengthMismatch();
        
        questionIDs = new bytes32[](length);
        
        // Initialize each question
        for (uint256 i = 0; i < length; i++) {
            questionIDs[i] = initialize(
                ancillaryDatas[i],
                rewardTokens[i],
                rewards[i],
                proposalBonds[i],
                livenesses[i]
            );
        }
        
        return questionIDs;
    }
    
    /// @notice Optimized resolve function
    /// @param questionID - The unique questionID
    function resolve(bytes32 questionID) external override {
        OptimizedQuestionData storage questionData = questions[questionID];
        
        // Check question state
        if (!_isInitialized(questionID)) revert NotInitialized();
        if (_getFlag(questionData, FLAG_PAUSED)) revert Paused();
        if (_getFlag(questionData, FLAG_RESOLVED)) revert Resolved();
        
        bytes memory ancillaryData = questionAncillaryData[questionID];
        if (ancillaryData.length == 0) revert NotInitialized();
        
        // Check if price is available
        if (!optimisticOracle.hasPrice(
            address(this),
            YES_OR_NO_IDENTIFIER,
            uint256(questionData.requestTimestamp),
            ancillaryData
        )) revert NotReadyToResolve();
        
        // Resolve the underlying market
        _resolve(questionID, questionData, ancillaryData);
    }
    
    /// @notice Batch resolve multiple questions
    /// @param questionIDs - Array of questionIDs to resolve
    function batchResolve(bytes32[] calldata questionIDs) external {
        for (uint256 i = 0; i < questionIDs.length; i++) {
            bytes32 questionID = questionIDs[i];
            // Skip if question already resolved, paused, or not ready
            if (ready(questionID)) {
                try this.resolve(questionID) {} catch {}
            }
        }
    }
    
    /// @notice Get the cached question data (compatible with the original interface)
    /// @param questionID - The unique questionID
    function getQuestion(bytes32 questionID) external view override returns (QuestionData memory) {
        OptimizedQuestionData storage optimizedData = questions[questionID];
        bytes memory ancillaryData = questionAncillaryData[questionID];
        
        // Convert to original QuestionData format for compatibility
        return QuestionData({
            requestTimestamp: uint256(optimizedData.requestTimestamp),
            reward: uint256(optimizedData.reward),
            proposalBond: uint256(optimizedData.proposalBond),
            liveness: uint256(optimizedData.liveness),
            emergencyResolutionTimestamp: uint256(optimizedData.emergencyResolutionTimestamp),
            resolved: _getFlag(optimizedData, FLAG_RESOLVED),
            paused: _getFlag(optimizedData, FLAG_PAUSED),
            reset: _getFlag(optimizedData, FLAG_RESET),
            refund: _getFlag(optimizedData, FLAG_REFUND),
            rewardToken: optimizedData.rewardToken,
            creator: optimizedData.creator,
            ancillaryData: ancillaryData
        });
    }
    
    /*///////////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////////*/
    
    /// @notice Flag a question for emergency resolution (with gas optimization)
    /// @param questionID - The unique questionID
    function flag(bytes32 questionID) external override onlyAdmin {
        OptimizedQuestionData storage questionData = questions[questionID];
        
        if (!_isInitialized(questionID)) revert NotInitialized();
        if (_getFlag(questionData, FLAG_FLAGGED)) revert Flagged();
        if (_getFlag(questionData, FLAG_RESOLVED)) revert Resolved();
        
        // Set emergency resolution timestamp and flags
        questionData.emergencyResolutionTimestamp = uint48(block.timestamp + EMERGENCY_SAFETY_PERIOD);
        _setFlag(questionData, FLAG_PAUSED, true);
        _setFlag(questionData, FLAG_FLAGGED, true);
        
        emit QuestionFlagged(questionID);
    }
    
    /// @notice Unflag a question (gas optimized)
    /// @param questionID - The unique questionID
    function unflag(bytes32 questionID) external override onlyAdmin {
        OptimizedQuestionData storage questionData = questions[questionID];
        
        if (!_isInitialized(questionID)) revert NotInitialized();
        if (!_getFlag(questionData, FLAG_FLAGGED)) revert NotFlagged();
        if (_getFlag(questionData, FLAG_RESOLVED)) revert Resolved();
        if (block.timestamp > uint256(questionData.emergencyResolutionTimestamp)) revert SafetyPeriodPassed();
        
        questionData.emergencyResolutionTimestamp = 0;
        _setFlag(questionData, FLAG_PAUSED, false);
        _setFlag(questionData, FLAG_FLAGGED, false);
        
        emit QuestionUnflagged(questionID);
    }
    
    /// @notice Reset a question (gas optimized)
    /// @param questionID - The unique questionID
    function reset(bytes32 questionID) external override onlyAdmin {
        OptimizedQuestionData storage questionData = questions[questionID];
        if (!_isInitialized(questionID)) revert NotInitialized();
        if (_getFlag(questionData, FLAG_RESOLVED)) revert Resolved();
        
        // Refund if needed
        if (_getFlag(questionData, FLAG_REFUND)) {
            TransferHelper._transfer(
                questionData.rewardToken,
                questionData.creator,
                uint256(questionData.reward)
            );
            _setFlag(questionData, FLAG_REFUND, false);
        }
        
        // Reset with updated approach
        _resetQuestion(msg.sender, questionID, questionData);
    }
    
    /// @notice Emergency resolve with optimization
    /// @param questionID - The unique questionID
    /// @param payouts - Payout array
    function emergencyResolve(bytes32 questionID, uint256[] calldata payouts) external override onlyAdmin {
        OptimizedQuestionData storage questionData = questions[questionID];
        
        if (!PayoutHelperLib.isValidPayoutArray(payouts)) revert InvalidPayouts();
        if (!_isInitialized(questionID)) revert NotInitialized();
        if (!_getFlag(questionData, FLAG_FLAGGED)) revert NotFlagged();
        if (block.timestamp < uint256(questionData.emergencyResolutionTimestamp)) revert SafetyPeriodNotPassed();
        
        // Set resolved flag
        _setFlag(questionData, FLAG_RESOLVED, true);
        
        // Refund if needed
        if (_getFlag(questionData, FLAG_REFUND)) {
            TransferHelper._transfer(
                questionData.rewardToken,
                questionData.creator,
                uint256(questionData.reward)
            );
        }
        
        // Cache the resolved payouts
        resolvedPayouts[questionID] = payouts;
        
        // Resolve market
        ctf.reportPayouts(questionID, payouts);
        
        emit QuestionEmergencyResolved(questionID, payouts);
        
        // Clean up storage to save gas (refund)
        delete questionAncillaryData[questionID];
    }
    
    /// @notice Pause with gas optimization
    /// @param questionID - The unique questionID
    function pause(bytes32 questionID) external override onlyAdmin {
        OptimizedQuestionData storage questionData = questions[questionID];
        
        if (!_isInitialized(questionID)) revert NotInitialized();
        if (_getFlag(questionData, FLAG_RESOLVED)) revert Resolved();
        
        _setFlag(questionData, FLAG_PAUSED, true);
        
        emit QuestionPaused(questionID);
    }
    
    /// @notice Unpause with gas optimization
    /// @param questionID - The unique questionID
    function unpause(bytes32 questionID) external override onlyAdmin {
        OptimizedQuestionData storage questionData = questions[questionID];
        if (!_isInitialized(questionID)) revert NotInitialized();
        
        _setFlag(questionData, FLAG_PAUSED, false);
        
        emit QuestionUnpaused(questionID);
    }
    
    /*///////////////////////////////////////////////////////////////////
                        OPTIMISTIC ORACLE CALLBACK
    //////////////////////////////////////////////////////////////////*/
    
    /// @notice Callback for dispute, optimized for gas
    function priceDisputed(
        bytes32,
        uint256,
        bytes memory ancillaryData,
        uint256
    ) external override onlyOptimisticOracle {
        bytes32 questionID = keccak256(ancillaryData);
        OptimizedQuestionData storage questionData = questions[questionID];
        
        // If already resolved, refund reward
        if (_getFlag(questionData, FLAG_RESOLVED)) {
            TransferHelper._transfer(
                questionData.rewardToken,
                questionData.creator,
                uint256(questionData.reward)
            );
            return;
        }
        
        // If already reset, set refund flag
        if (_getFlag(questionData, FLAG_RESET)) {
            _setFlag(questionData, FLAG_REFUND, true);
            return;
        }
        
        // Reset the question
        _resetQuestion(address(this), questionID, questionData);
    }
    
    /*///////////////////////////////////////////////////////////////////
                        UTILITY VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////*/
    
    /// @notice Check if question is ready for resolution
    function ready(bytes32 questionID) public view override returns (bool) {
        OptimizedQuestionData storage questionData = questions[questionID];
        
        if (!_isInitialized(questionID)) return false;
        if (_getFlag(questionData, FLAG_PAUSED)) return false;
        if (_getFlag(questionData, FLAG_RESOLVED)) return false;
        
        bytes memory ancillaryData = questionAncillaryData[questionID];
        if (ancillaryData.length == 0) return false;
        
        return optimisticOracle.hasPrice(
            address(this),
            YES_OR_NO_IDENTIFIER,
            uint256(questionData.requestTimestamp),
            ancillaryData
        );
    }
    
    /// @notice Check if question is initialized
    function isInitialized(bytes32 questionID) public view override returns (bool) {
        return _isInitialized(questionID);
    }
    
    /// @notice Check if question is flagged
    function isFlagged(bytes32 questionID) public view override returns (bool) {
        return _getFlag(questions[questionID], FLAG_FLAGGED);
    }
    
    /// @notice Get payouts for a question
    function getExpectedPayouts(bytes32 questionID) public view override returns (uint256[] memory) {
        OptimizedQuestionData storage questionData = questions[questionID];
        
        // Return cached payouts if already resolved
        if (_getFlag(questionData, FLAG_RESOLVED) && resolvedPayouts[questionID].length > 0) {
            return resolvedPayouts[questionID];
        }
        
        // Validation checks
        if (!_isInitialized(questionID)) revert NotInitialized();
        if (_getFlag(questionData, FLAG_FLAGGED)) revert Flagged();
        if (_getFlag(questionData, FLAG_PAUSED)) revert Paused();
        
        bytes memory ancillaryData = questionAncillaryData[questionID];
        if (ancillaryData.length == 0) revert NotInitialized();
        
        if (!optimisticOracle.hasPrice(
            address(this),
            YES_OR_NO_IDENTIFIER,
            uint256(questionData.requestTimestamp),
            ancillaryData
        )) revert PriceNotAvailable();
        
        // Get price from OO
        int256 price = optimisticOracle.getRequest(
            address(this),
            YES_OR_NO_IDENTIFIER,
            uint256(questionData.requestTimestamp),
            ancillaryData
        ).resolvedPrice;
        
        return _constructPayouts(price);
    }
    
    /*///////////////////////////////////////////////////////////////////
                        INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////*/
    
    /// @notice Helper to check if a question is initialized
    function _isInitialized(bytes32 questionID) internal view returns (bool) {
        return questions[questionID].ancillaryDataHash != bytes32(0);
    }
    
    /// @notice Set a flag on a question
    function _setFlag(OptimizedQuestionData storage data, uint8 flag, bool value) internal {
        if (value) {
            data.flags = data.flags | flag;
        } else {
            data.flags = data.flags & ~flag;
        }
    }
    
    /// @notice Get a flag value from a question
    function _getFlag(OptimizedQuestionData storage data, uint8 flag) internal view returns (bool) {
        return (data.flags & flag) != 0;
    }
    
    /// @notice Request price from OO with gas optimization
    function _requestPrice(
        address requestor,
        uint256 requestTimestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond,
        uint256 liveness
    ) internal {
        if (reward > 0) {
            // Transfer reward from requestor if not the adapter
            if (requestor != address(this)) {
                TransferHelper._transferFromERC20(rewardToken, requestor, address(this), reward);
            }
            
            // Approve OO to spend reward token (only once)
            if (IERC20(rewardToken).allowance(address(this), address(optimisticOracle)) < reward) {
                IERC20(rewardToken).approve(address(optimisticOracle), type(uint256).max);
            }
        }
        
        // Request price from OO
        optimisticOracle.requestPrice(
            YES_OR_NO_IDENTIFIER,
            requestTimestamp,
            ancillaryData,
            IERC20(rewardToken),
            reward
        );
        
        // Configure OO with a single call where possible
        optimisticOracle.setEventBased(YES_OR_NO_IDENTIFIER, requestTimestamp, ancillaryData);
        
        // Set callbacks
        optimisticOracle.setCallbacks(
            YES_OR_NO_IDENTIFIER,
            requestTimestamp,
            ancillaryData,
            false, // No callback on priceProposed
            true,  // Callback on priceDisputed
            false  // No callback on priceSettled
        );
        
        // Set bond and liveness if specified
        if (bond > 0) {
            optimisticOracle.setBond(YES_OR_NO_IDENTIFIER, requestTimestamp, ancillaryData, bond);
        }
        
        if (liveness > 0) {
            optimisticOracle.setCustomLiveness(YES_OR_NO_IDENTIFIER, requestTimestamp, ancillaryData, liveness);
        }
    }
    
    /// @notice Reset a question with a new request
    function _resetQuestion(address requestor, bytes32 questionID, OptimizedQuestionData storage questionData) internal {
        bytes memory ancillaryData = questionAncillaryData[questionID];
        if (ancillaryData.length == 0) revert NotInitialized();
        
        // Update timestamp and flags
        questionData.requestTimestamp = uint48(block.timestamp);
        _setFlag(questionData, FLAG_RESET, true);
        
        // Request new price from OO
        _requestPrice(
            requestor,
            block.timestamp,
            ancillaryData,
            questionData.rewardToken,
            uint256(questionData.reward),
            uint256(questionData.proposalBond),
            uint256(questionData.liveness)
        );
        
        emit QuestionReset(questionID);
    }
    
    /// @notice Resolve the question with OO price
    function _resolve(bytes32 questionID, OptimizedQuestionData storage questionData, bytes memory ancillaryData) internal {
        // Get price from OO
        int256 price = optimisticOracle.settleAndGetPrice(
            YES_OR_NO_IDENTIFIER,
            uint256(questionData.requestTimestamp),
            ancillaryData
        );
        
        // If ignore price, reset the question
        if (price == type(int256).min) {
            _resetQuestion(address(this), questionID, questionData);
            return;
        }
        
        // Set resolved flag
        _setFlag(questionData, FLAG_RESOLVED, true);
        
        // Refund if needed
        if (_getFlag(questionData, FLAG_REFUND)) {
            TransferHelper._transfer(
                questionData.rewardToken,
                questionData.creator,
                uint256(questionData.reward)
            );
        }
        
        // Construct payouts
        uint256[] memory payouts = _constructPayouts(price);
        
        // Cache payouts
        resolvedPayouts[questionID] = payouts;
        
        // Resolve market
        ctf.reportPayouts(questionID, payouts);
        
        emit QuestionResolved(questionID, price, payouts);
        
        // Clean up storage to save gas (refund)
        delete questionAncillaryData[questionID];
    }
    
    /// @notice Construct payouts from price
    function _constructPayouts(int256 price) internal pure returns (uint256[] memory) {
        uint256[] memory payouts = new uint256[](2);
        
        // Validate price
        if (price != 0 && price != 0.5 ether && price != 1 ether) revert InvalidOOPrice();
        
        if (price == 0) {
            // NO: [0, 1]
            payouts[0] = 0;
            payouts[1] = 1;
        } else if (price == 0.5 ether) {
            // UNKNOWN: [1, 1]
            payouts[0] = 1;
            payouts[1] = 1;
        } else {
            // YES: [1, 0]
            payouts[0] = 1;
            payouts[1] = 0;
        }
        
        return payouts;
    }
    
    /*///////////////////////////////////////////////////////////////////
                            ERROR DEFINITIONS
    //////////////////////////////////////////////////////////////////*/
    
    error ArrayLengthMismatch();
}