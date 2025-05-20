# Polymarket's Core Smart Contracts

## 1. ConditionalTokens
**Purpose**: Manages conditional tokens, creating the fundamental foundation for prediction markets.
**Key Functions**:
* Create conditions for possible outcomes
* Split and merge positions
* Mechanism to convert tokens into rewards after results are determined
* Uses the ERC-1155 standard for diverse tokens
**Significance**:
* Is the heart of the system, handling core logic for creating and resolving prediction markets
* Allows users to hold positions on different outcomes

## 2. FixedProductMarketMaker (FPMM)
**Purpose**: Provides liquidity and automatic pricing for conditional tokens.
**Key Functions**:
* Implements Automated Market Maker (AMM) mechanism
* Allows users to buy/sell outcome tokens
* Manages liquidity and transaction fees
* Calculates prices based on supply/demand
**Significance**:
* Ensures markets always have liquidity
* Determines the price of possible outcomes, reflecting market probabilities
* Provides a profit mechanism for liquidity providers

## 3. UmaCtfAdapter
**Purpose**: Connects to UMA Oracle to resolve markets based on real-world results.
**Key Functions**:
* Initializes questions/markets on UMA
* Requests and receives results from UMA Optimistic Oracle
* Converts UMA results to formats compatible with ConditionalTokens
* Provides mechanisms for dispute handling and emergency resolution
**Significance**:
* Ensures decentralization in market resolution
* Provides a reliable mechanism to report real-world results
* Serves as a bridge between the conditional token system and oracles

## 4. CTFExchange
**Purpose**: Supports conditional token trading through a central limit order book (CLOB).
**Key Functions**:
* Manages the orderbook for conditional tokens
* Processes buy/sell orders between users
* Applies transaction fees and restrictions
* Integrates with other contracts to execute trades
**Significance**:
* Complements the AMM mechanism, allowing for better liquidity trading
* Provides limit order book functionality, more complex than simple AMM
* Facilitates advanced market-making activities

## Relationship between contracts:
* **ConditionalTokens** provides the basic token infrastructure
* **FPMM** uses ConditionalTokens to create markets with liquidity
* **UmaCtfAdapter** connects ConditionalTokens with oracles to resolve outcomes
* **CTFExchange** complements FPMM by providing an orderbook trading mechanism

This smart contract architecture creates a complete ecosystem for prediction markets, from position creation to liquidity provision, trading, and market resolution.
