// SPDX-License-Identifier: MIT
pragma solidity ^0.5.1;

import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";
import { CTHelpers } from "./CTHelpers.sol";

/**
 * @title OptimizedConditionalTokens
 * @notice Gas-optimized implementation of Conditional Tokens for prediction markets
 */
contract OptimizedConditionalTokens is ERC1155 {
    using SafeMath for uint256;

    /// @dev Events
    event ConditionPreparation(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount
    );

    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount,
        uint[] payoutNumerators
    );

    event PositionSplit(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint[] partition,
        uint amount
    );
    
    event PositionsMerge(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint[] partition,
        uint amount
    );
    
    event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint[] indexSets,
        uint payout
    );

    event BatchPositionSplit(
        address indexed stakeholder,
        uint operations
    );

    event BatchPositionsMerge(
        address indexed stakeholder,
        uint operations
    );

    /// Storage for condition payouts
    mapping(bytes32 => uint[]) public payoutNumerators;
    mapping(bytes32 => uint) public payoutDenominator;
    
    /// Cache for commonly used condition data
    struct ConditionCache {
        uint outcomeSlotCount;
        uint fullIndexSet;
    }
    
    // Cache to avoid recalculating values
    mapping(bytes32 => ConditionCache) public conditionCache;
    
    /// Approval for all with privileged access for better batching
    mapping(address => mapping(address => uint256)) public transferAllowances;
    
    // Constants
    uint256 private constant MAX_OUTCOME_SLOTS = 256;

    /**
     * @dev Prepare a condition by initializing its payout vector
     * @param oracle Account assigned to report the result
     * @param questionId Identifier for the question
     * @param outcomeSlotCount Number of outcome slots
     */
    function prepareCondition(address oracle, bytes32 questionId, uint outcomeSlotCount) external {
        require(outcomeSlotCount <= MAX_OUTCOME_SLOTS, "too many outcome slots");
        require(outcomeSlotCount > 1, "there should be more than one outcome slot");
        
        bytes32 conditionId = CTHelpers.getConditionId(oracle, questionId, outcomeSlotCount);
        require(payoutNumerators[conditionId].length == 0, "condition already prepared");
        
        // Initialize payout numerators array
        payoutNumerators[conditionId] = new uint[](outcomeSlotCount);
        
        // Cache condition data to save gas on future operations
        uint fullIndexSet = (1 << outcomeSlotCount) - 1;
        conditionCache[conditionId] = ConditionCache({
            outcomeSlotCount: outcomeSlotCount,
            fullIndexSet: fullIndexSet
        });
        
        emit ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);
    }

    /**
     * @dev Report results of a condition
     * @param questionId Question ID the oracle is answering for
     * @param payouts Oracle's answer
     */
    function reportPayouts(bytes32 questionId, uint[] calldata payouts) external {
        uint outcomeSlotCount = payouts.length;
        require(outcomeSlotCount > 1, "there should be more than one outcome slot");
        
        bytes32 conditionId = CTHelpers.getConditionId(msg.sender, questionId, outcomeSlotCount);
        require(payoutNumerators[conditionId].length == outcomeSlotCount, "condition not prepared or found");
        require(payoutDenominator[conditionId] == 0, "payout denominator already set");

        uint den = 0;
        for (uint i = 0; i < outcomeSlotCount; i++) {
            uint num = payouts[i];
            den = den.add(num);
            
            require(payoutNumerators[conditionId][i] == 0, "payout numerator already set");
            payoutNumerators[conditionId][i] = num;
        }
        
        require(den > 0, "payout is all zeroes");
        payoutDenominator[conditionId] = den;
        
        emit ConditionResolution(conditionId, msg.sender, questionId, outcomeSlotCount, payoutNumerators[conditionId]);
    }

    /**
     * @dev Optimized split position function
     * @param collateralToken Address of the positions' backing collateral token
     * @param parentCollectionId ID of the outcome collections common to positions
     * @param conditionId ID of the condition to split on
     * @param partition Array of disjoint index sets representing a partition of outcomes
     * @param amount Amount of collateral or stake to split
     */
    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external {
        require(partition.length > 1, "got empty or singleton partition");
        
        // Use cached condition data
        ConditionCache memory condition = conditionCache[conditionId];
        require(condition.outcomeSlotCount > 0, "condition not prepared yet");
        
        uint fullIndexSet = condition.fullIndexSet;
        uint freeIndexSet = fullIndexSet;
        
        // Pre-allocate arrays to avoid multiple memory allocations
        uint[] memory positionIds = new uint[](partition.length);
        uint[] memory amounts = new uint[](partition.length);
        
        // Validate partition and prepare minting data
        for (uint i = 0; i < partition.length; i++) {
            uint indexSet = partition[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            require((indexSet & freeIndexSet) == indexSet, "partition not disjoint");
            
            freeIndexSet ^= indexSet;
            
            bytes32 collectionId = CTHelpers.getCollectionId(parentCollectionId, conditionId, indexSet);
            positionIds[i] = CTHelpers.getPositionId(collateralToken, collectionId);
            amounts[i] = amount;
        }

        // Handle splitting logic
        if (freeIndexSet == 0) {
            // Splitting from collateral or parent position
            if (parentCollectionId == bytes32(0)) {
                // Transfer collateral from sender
                require(collateralToken.transferFrom(msg.sender, address(this), amount), "could not receive collateral tokens");
            } else {
                // Burn parent position
                _burn(
                    msg.sender,
                    CTHelpers.getPositionId(collateralToken, parentCollectionId),
                    amount
                );
            }
        } else {
            // Splitting from a partial position
            _burn(
                msg.sender,
                CTHelpers.getPositionId(collateralToken,
                    CTHelpers.getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)),
                amount
            );
        }

        // Mint new positions
        _batchMint(msg.sender, positionIds, amounts, "");
        
        emit PositionSplit(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /**
     * @dev Batch split multiple positions in a single transaction
     * @param params Array of SplitParams structs
     */
    function batchSplitPosition(SplitParams[] calldata params) external {
        uint operationCount = 0;
        
        for (uint i = 0; i < params.length; i++) {
            SplitParams memory p = params[i];
            
            // Use cached condition data
            ConditionCache memory condition = conditionCache[p.conditionId];
            require(condition.outcomeSlotCount > 0, "condition not prepared yet");
            
            uint fullIndexSet = condition.fullIndexSet;
            uint freeIndexSet = fullIndexSet;
            
            // Pre-allocate arrays to avoid multiple memory allocations
            uint[] memory positionIds = new uint[](p.partition.length);
            uint[] memory amounts = new uint[](p.partition.length);
            
            // Validate partition and prepare minting data
            for (uint j = 0; j < p.partition.length; j++) {
                uint indexSet = p.partition[j];
                
                // Skip in-depth validation for gas saving, but ensure basic safety
                if (indexSet == 0 || indexSet >= fullIndexSet || (indexSet & freeIndexSet) != indexSet) {
                    continue; // Skip invalid entries
                }
                
                freeIndexSet ^= indexSet;
                
                bytes32 collectionId = CTHelpers.getCollectionId(p.parentCollectionId, p.conditionId, indexSet);
                positionIds[j] = CTHelpers.getPositionId(p.collateralToken, collectionId);
                amounts[j] = p.amount;
            }

            // Handle splitting logic
            if (freeIndexSet == 0) {
                // Splitting from collateral or parent position
                if (p.parentCollectionId == bytes32(0)) {
                    // Transfer collateral from sender
                    bool success = p.collateralToken.transferFrom(msg.sender, address(this), p.amount);
                    if (!success) continue; // Skip if transfer fails
                } else {
                    // Burn parent position
                    _burn(
                        msg.sender,
                        CTHelpers.getPositionId(p.collateralToken, p.parentCollectionId),
                        p.amount
                    );
                }
            } else {
                // Splitting from a partial position
                _burn(
                    msg.sender,
                    CTHelpers.getPositionId(p.collateralToken,
                        CTHelpers.getCollectionId(p.parentCollectionId, p.conditionId, fullIndexSet ^ freeIndexSet)),
                    p.amount
                );
            }

            // Mint new positions
            _batchMint(msg.sender, positionIds, amounts, "");
            operationCount++;
        }
        
        emit BatchPositionSplit(msg.sender, operationCount);
    }

    /**
     * @dev Optimized merge positions function
     * @param collateralToken Address of the positions' backing collateral token
     * @param parentCollectionId ID of the outcome collections common to positions
     * @param conditionId ID of the condition to merge on
     * @param partition Array of disjoint index sets representing a partition of outcomes
     * @param amount Amount to merge
     */
    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external {
        require(partition.length > 1, "got empty or singleton partition");
        
        // Use cached condition data
        ConditionCache memory condition = conditionCache[conditionId];
        require(condition.outcomeSlotCount > 0, "condition not prepared yet");
        
        uint fullIndexSet = condition.fullIndexSet;
        uint freeIndexSet = fullIndexSet;
        
        // Pre-allocate arrays to avoid multiple memory allocations
        uint[] memory positionIds = new uint[](partition.length);
        uint[] memory amounts = new uint[](partition.length);
        
        // Validate partition and prepare burning data
        for (uint i = 0; i < partition.length; i++) {
            uint indexSet = partition[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            require((indexSet & freeIndexSet) == indexSet, "partition not disjoint");
            
            freeIndexSet ^= indexSet;
            
            bytes32 collectionId = CTHelpers.getCollectionId(parentCollectionId, conditionId, indexSet);
            positionIds[i] = CTHelpers.getPositionId(collateralToken, collectionId);
            amounts[i] = amount;
        }
        
        // Burn positions
        _batchBurn(msg.sender, positionIds, amounts);

        // Handle merging logic
        if (freeIndexSet == 0) {
            // Merging into collateral or parent position
            if (parentCollectionId == bytes32(0)) {
                // Transfer collateral to sender
                require(collateralToken.transfer(msg.sender, amount), "could not send collateral tokens");
            } else {
                // Mint parent position
                _mint(
                    msg.sender,
                    CTHelpers.getPositionId(collateralToken, parentCollectionId),
                    amount,
                    ""
                );
            }
        } else {
            // Merging into a partial position
            _mint(
                msg.sender,
                CTHelpers.getPositionId(collateralToken,
                    CTHelpers.getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)),
                amount,
                ""
            );
        }

        emit PositionsMerge(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /**
     * @dev Batch merge multiple position sets in a single transaction
     * @param params Array of MergeParams structs
     */
    function batchMergePositions(MergeParams[] calldata params) external {
        uint operationCount = 0;
        
        for (uint i = 0; i < params.length; i++) {
            MergeParams memory p = params[i];
            
            // Use cached condition data
            ConditionCache memory condition = conditionCache[p.conditionId];
            if (condition.outcomeSlotCount == 0) continue; // Skip if condition not prepared
            
            uint fullIndexSet = condition.fullIndexSet;
            uint freeIndexSet = fullIndexSet;
            
            // Pre-allocate arrays to avoid multiple memory allocations
            uint[] memory positionIds = new uint[](p.partition.length);
            uint[] memory amounts = new uint[](p.partition.length);
            
            // Validate partition and prepare burning data
            bool validPartition = true;
            for (uint j = 0; j < p.partition.length; j++) {
                uint indexSet = p.partition[j];
                
                // Skip in-depth validation for gas saving, but ensure basic safety
                if (indexSet == 0 || indexSet >= fullIndexSet || (indexSet & freeIndexSet) != indexSet) {
                    validPartition = false;
                    break;
                }
                
                freeIndexSet ^= indexSet;
                
                bytes32 collectionId = CTHelpers.getCollectionId(p.parentCollectionId, p.conditionId, indexSet);
                positionIds[j] = CTHelpers.getPositionId(p.collateralToken, collectionId);
                amounts[j] = p.amount;
            }
            
            if (!validPartition) continue;
            
            // Burn positions
            _batchBurn(msg.sender, positionIds, amounts);

            // Handle merging logic
            if (freeIndexSet == 0) {
                // Merging into collateral or parent position
                if (p.parentCollectionId == bytes32(0)) {
                    // Transfer collateral to sender
                    bool success = p.collateralToken.transfer(msg.sender, p.amount);
                    if (!success) continue; // Skip if transfer fails
                } else {
                    // Mint parent position
                    _mint(
                        msg.sender,
                        CTHelpers.getPositionId(p.collateralToken, p.parentCollectionId),
                        p.amount,
                        ""
                    );
                }
            } else {
                // Merging into a partial position
                _mint(
                    msg.sender,
                    CTHelpers.getPositionId(p.collateralToken,
                        CTHelpers.getCollectionId(p.parentCollectionId, p.conditionId, fullIndexSet ^ freeIndexSet)),
                    p.amount,
                    ""
                );
            }
            
            operationCount++;
        }
        
        emit BatchPositionsMerge(msg.sender, operationCount);
    }

    /**
     * @dev Optimized redeem positions function
     * @param collateralToken Collateral token backing the positions
     * @param parentCollectionId Parent collection ID
     * @param conditionId ID of the condition to redeem for
     * @param indexSets Array of index sets to redeem
     */
    function redeemPositions(
        IERC20 collateralToken, 
        bytes32 parentCollectionId, 
        bytes32 conditionId, 
        uint[] calldata indexSets
    ) external {
        uint den = payoutDenominator[conditionId];
        require(den > 0, "result for condition not received yet");
        
        // Get condition data from cache
        ConditionCache memory condition = conditionCache[conditionId];
        require(condition.outcomeSlotCount > 0, "condition not prepared yet");
        
        uint fullIndexSet = condition.fullIndexSet;
        uint totalPayout = 0;
        
        // Calculate total payout across all index sets
        for (uint i = 0; i < indexSets.length; i++) {
            uint indexSet = indexSets[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            
            uint positionId = CTHelpers.getPositionId(
                collateralToken,
                CTHelpers.getCollectionId(parentCollectionId, conditionId, indexSet)
            );

            // Calculate payout numerator for this index set
            uint payoutNumerator = 0;
            uint[] storage nums = payoutNumerators[conditionId];
            
            // Use bit operations to check which outcomes are included in this index set
            for (uint j = 0; j < condition.outcomeSlotCount; j++) {
                if (indexSet & (1 << j) != 0) {
                    payoutNumerator = payoutNumerator.add(nums[j]);
                }
            }

            // Calculate payout for this position
            uint payoutStake = balanceOf(msg.sender, positionId);
            if (payoutStake > 0) {
                totalPayout = totalPayout.add(payoutStake.mul(payoutNumerator).div(den));
                _burn(msg.sender, positionId, payoutStake);
            }
        }

        // Issue payout
        if (totalPayout > 0) {
            if (parentCollectionId == bytes32(0)) {
                require(collateralToken.transfer(msg.sender, totalPayout), "could not transfer payout to message sender");
            } else {
                _mint(
                    msg.sender, 
                    CTHelpers.getPositionId(collateralToken, parentCollectionId), 
                    totalPayout, 
                    ""
                );
            }
        }
        
        emit PayoutRedemption(msg.sender, collateralToken, parentCollectionId, conditionId, indexSets, totalPayout);
    }

    /**
     * @dev Batch redeem for multiple conditions
     * @param params Array of RedeemParams structs
     */
    function batchRedeemPositions(RedeemParams[] calldata params) external {
        for (uint i = 0; i < params.length; i++) {
            RedeemParams memory p = params[i];
            
            uint den = payoutDenominator[p.conditionId];
            if (den == 0) continue; // Skip if not resolved yet
            
            // Get condition data from cache
            ConditionCache memory condition = conditionCache[p.conditionId];
            if (condition.outcomeSlotCount == 0) continue; // Skip if not prepared
            
            uint fullIndexSet = condition.fullIndexSet;
            uint totalPayout = 0;
            
            // Calculate total payout across all index sets
            for (uint j = 0; j < p.indexSets.length; j++) {
                uint indexSet = p.indexSets[j];
                if (indexSet == 0 || indexSet >= fullIndexSet) continue; // Skip invalid
                
                uint positionId = CTHelpers.getPositionId(
                    p.collateralToken,
                    CTHelpers.getCollectionId(p.parentCollectionId, p.conditionId, indexSet)
                );

                // Calculate payout numerator for this index set
                uint payoutNumerator = 0;
                uint[] storage nums = payoutNumerators[p.conditionId];
                
                // Use bit operations to check which outcomes are included in this index set
                for (uint k = 0; k < condition.outcomeSlotCount; k++) {
                    if (indexSet & (1 << k) != 0) {
                        payoutNumerator = payoutNumerator.add(nums[k]);
                    }
                }

                // Calculate payout for this position
                uint payoutStake = balanceOf(msg.sender, positionId);
                if (payoutStake > 0) {
                    totalPayout = totalPayout.add(payoutStake.mul(payoutNumerator).div(den));
                    _burn(msg.sender, positionId, payoutStake);
                }
            }

            // Issue payout
            if (totalPayout > 0) {
                if (p.parentCollectionId == bytes32(0)) {
                    bool success = p.collateralToken.transfer(msg.sender, totalPayout);
                    if (!success) continue; // Skip if transfer fails
                } else {
                    _mint(
                        msg.sender, 
                        CTHelpers.getPositionId(p.collateralToken, p.parentCollectionId), 
                        totalPayout, 
                        ""
                    );
                }
                
                emit PayoutRedemption(msg.sender, p.collateralToken, p.parentCollectionId, p.conditionId, p.indexSets, totalPayout);
            }
        }
    }

    /**
     * @dev Set allowance for a spender to transfer tokens on behalf of the approver
     * @param spender Address allowed to spend the tokens
     * @param amount Amount of tokens allowed to spend
     */
    function approve(address spender, uint256 amount) external {
        transferAllowances[msg.sender][spender] = amount;
    }

    /**
     * @dev Get the outcome slot count of a condition
     * @param conditionId ID of the condition
     * @return Number of outcome slots
     */
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint) {
        return conditionCache[conditionId].outcomeSlotCount;
    }

    /**
     * @dev Get the condition ID
     * @param oracle Oracle address
     * @param questionId Question identifier
     * @param outcomeSlotCount Number of outcome slots
     * @return Condition ID
     */
    function getConditionId(address oracle, bytes32 questionId, uint outcomeSlotCount) external pure returns (bytes32) {
        return CTHelpers.getConditionId(oracle, questionId, outcomeSlotCount);
    }

    /**
     * @dev Get the collection ID
     * @param parentCollectionId Parent collection ID
     * @param conditionId Condition ID
     * @param indexSet Index set
     * @return Collection ID
     */
    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint indexSet) external view returns (bytes32) {
        return CTHelpers.getCollectionId(parentCollectionId, conditionId, indexSet);
    }

    /**
     * @dev Get the position ID
     * @param collateralToken Collateral token
     * @param collectionId Collection ID
     * @return Position ID
     */
    function getPositionId(IERC20 collateralToken, bytes32 collectionId) external pure returns (uint) {
        return CTHelpers.getPositionId(collateralToken, collectionId);
    }
    
    /**
     * @dev Struct for batch split operations
     */
    struct SplitParams {
        IERC20 collateralToken;
        bytes32 parentCollectionId;
        bytes32 conditionId;
        uint[] partition;
        uint amount;
    }
    
    /**
     * @dev Struct for batch merge operations
     */
    struct MergeParams {
        IERC20 collateralToken;
        bytes32 parentCollectionId;
        bytes32 conditionId;
        uint[] partition;
        uint amount;
    }
    
    /**
     * @dev Struct for batch redeem operations
     */
    struct RedeemParams {
        IERC20 collateralToken;
        bytes32 parentCollectionId;
        bytes32 conditionId;
        uint[] indexSets;
    }
}