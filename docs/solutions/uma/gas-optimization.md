# UMA - Gas Optimization

**Source**: [GasOptimizedUmaAdapter.sol](../../contracts//GasOptimizedUmaAdapter.sol)

The source code has been significantly optimized to reduce gas fees through the following methods:

1. **Data Storage Optimization**:
   * Replaced boolean variables with bit flags in a uint8 (saving 4 slots)
   * Reduced size from uint256 to uint128, uint64, uint48 depending on the field
   * Stored hash of ancillaryData instead of the entire content

2. **Smart Memory Management**:
   * Deleted ancillaryData after resolution to refund gas
   * Stored resolved results to avoid recalculation
   * Used calldata instead of memory when possible

3. **Batch Processing**:
   * Added batchInitialize and batchResolve functions to process multiple questions simultaneously
   * Optimized batching process with try/catch to prevent reverting the entire batch

4. **Logic Optimization**:
   * Reduced number of storage reads/writes
   * Used efficient flag processing methods
   * Cleaned up unnecessary storage after use

5. **Backward Compatibility**:
   * Maintained external interfaces
   * Converted optimized data to old format when needed

These changes can significantly reduce gas costs, especially in common operations such as market initialization and resolution, making the use of UMA Oracle more economically viable.