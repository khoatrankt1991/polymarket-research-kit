# Assessment of Individual FPMM Contracts per Market

Polymarket's current model, where each market has its own separate FixedProductMarketMaker (FPMM) contract, presents both significant advantages and disadvantages:

## Advantages of Separate FPMM Contracts

1. **Independence and Isolation**:
  - Each market is completely isolated, issues in one market don't affect others
  - If one FPMM contract has a bug or is exploited, only that market is affected

2. **Market-Specific Customization**:
  - Different parameters (fees, timeframes, oracle mechanisms) can be configured for each market
  - Easy to implement optimizations or special mechanisms for specific market types

3. **Easier Upgrades and Improvements**:
  - New FPMM versions can be deployed for new markets without affecting existing ones
  - Allows for safe testing of improvements

4. **Clear Liquidity Management**:
  - Liquidity is managed separately for each market
  - Easy to track performance and statistics of individual markets

## Disadvantages of Separate FPMM Contracts

1. **High Deployment Costs**:
  - Each new FPMM contract incurs deployment fees
  - Results in significant total gas costs when many markets are created

2. **Blockchain Resource Inefficiency**:
  - Each contract adds substantial storage to the blockchain
  - Leads to "blockchain bloat" as the system grows

3. **Liquidity Fragmentation**:
  - Liquidity is split into many separate pools rather than concentrated
  - Reduces overall efficiency and increases slippage for users

4. **Complex Management and Monitoring**:
  - Difficulty in tracking and managing a large number of FPMM contracts
  - Increases error risk and complicates updates

5. **Code Redundancy**:
  - The same code is deployed multiple times, creating redundancy
  - Increases the overall attack surface of the system

## Alternative Solution: Factory & Clone Pattern

A better approach could be using the Factory & Clone Pattern:

```solidity
contract FPMMFactory {
   address public fpmm_implementation;
   mapping(bytes32 => address) public market_to_fpmm;
   
   function createFPMM(bytes32 marketId, address collateralToken, bytes32 conditionId, uint fee) external returns (address) {
       // Clone implementation contract instead of deploying new one
       address newFPMM = clone(fpmm_implementation);
       
       // Initialize the cloned FPMM
       FPMM(newFPMM).initialize(collateralToken, conditionId, fee);
       
       // Store reference
       market_to_fpmm[marketId] = newFPMM;
       
       return newFPMM;
   }
   
   function clone(address implementation) internal returns (address instance) {
       // EIP-1167 minimal proxy implementation
       // ...implementation code...
   }
}
```

## Benefits of the Factory & Clone Pattern:

1. **Significant Gas Cost Reduction:**
- Deploying a clone costs only ~10% of the gas compared to a full deployment
- Only reference bytecode is stored on-chain

2. **Higher Consistency:**
- All markets use the same implementation code
- Easier to update global parameters

3. **Centralized Management with Decentralized Execution:**
- Maintains independence of markets
- But manages them easily through the Factory

4. **Better Upgrade Capabilities:**
- Can implement upgrades to the FPMM model from a central location
- Supports multiple versions through multiple Factories