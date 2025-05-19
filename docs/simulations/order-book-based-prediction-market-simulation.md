# Order Book-Based Prediction Market Simulation (with UMA Oracle and CtfExchange)

## 1. Market Initialization

```javascript
// Initialize market via UMA Adapter
await umaCtfAdapter.initialize(
    ancillaryData,           // Ancillary data for UMA
    usdcAddress,             // Collateral token
    1000 * 10^6,             // Reward (1,000 USDC)
    500 * 10^6,              // Proposal bond (500 USDC)
    7200                     // Liveness (2 hours)
);
// This will call ctf.prepareCondition internally
```

## 2. Initial Liquidity Provision by LP

```javascript
// LP approves USDC
await usdc.approve(conditionalTokens.address, "10000000000"); // 10,000 USDC

// LP creates initial positions
await conditionalTokens.splitPosition(
    usdc.address,            // Collateral token
    marketId,                // Market ID
    conditionId,             // Condition ID
    [1, 1],                  // Partition (YES/NO)
    "10000000000"            // Amount of USDC
);

// LP receives 5,000 YES tokens and 5,000 NO tokens
const lpYesBalance = await conditionalTokens.balanceOf(lp.address, yesTokenId);
const lpNoBalance = await conditionalTokens.balanceOf(lp.address, noTokenId);
// lpYesBalance = 5000
// lpNoBalance = 5000
```

## 3. LP Places Initial Sell Orders via CtfExchange

```javascript
// LP places a sell order for YES tokens on CtfExchange
await ctfExchange.createOrder({
    maker: lp.address,
    isBuy: false,
    outcome: "YES",
    price: "0.55",           // Sell price for YES
    size: "2000",            // Amount of YES tokens
    expiration: futureTime
});

// LP places a sell order for NO tokens on CtfExchange
await ctfExchange.createOrder({
    maker: lp.address,
    isBuy: false,
    outcome: "NO",
    price: "0.55",           // Sell price for NO
    size: "2000",            // Amount of NO tokens
    expiration: futureTime
});
```

## 4. Users Buy Tokens via CtfExchange

```javascript
// Alice places a buy order for YES tokens on CtfExchange
await ctfExchange.createOrder({
    maker: alice.address,
    isBuy: true,
    outcome: "YES",
    price: "0.55",
    size: "1000",
    expiration: futureTime
});

// Alice's order matches with LP's sell order
await ctfExchange.matchOrders(orderIdAlice, orderIdLP);
// CtfExchange transfers 1000 YES tokens to Alice, 550 USDC to LP
const aliceYesBalance = await conditionalTokens.balanceOf(alice.address, yesTokenId);
// aliceYesBalance = 1000
```

## 5. Secondary Market Trading via CtfExchange

```javascript
// Alice places a sell order for 500 YES tokens on CtfExchange
await ctfExchange.createOrder({
    maker: alice.address,
    isBuy: false,
    outcome: "YES",
    price: "0.60",
    size: "500",
    expiration: futureTime
});

// Charlie places a buy order for 500 YES tokens on CtfExchange
await ctfExchange.createOrder({
    maker: charlie.address,
    isBuy: true,
    outcome: "YES",
    price: "0.60",
    size: "500",
    expiration: futureTime
});

// Match orders between Alice and Charlie
await ctfExchange.matchOrders(orderIdCharlie, orderIdAlice);
// Alice receives 300 USDC (500 * 0.60), Charlie receives 500 YES tokens
```

## 6. Market Resolution via UMA Oracle

```javascript
// 1. Submit resolution request to UMA Oracle
await umaCtfAdapter.requestResolution(
    conditionId,
    ancillaryData
);

// 2. UMA token holders vote and confirm the result
// 3. UMA Oracle returns the result (e.g. YES wins)
// 4. Adapter calls resolve() to update the result (resolve() calls ctf.reportPayouts internally)
await umaCtfAdapter.resolve(
    conditionId,
    payouts // [1, 0] if YES wins, [0, 1] if NO wins
);

// YES token holders can redeem
await conditionalTokens.redeemPositions(
    usdc.address,
    marketId,
    conditionId,
    [1, 0]                   // Only redeem YES tokens
);

// Final results:
// Alice: 500 YES tokens * 1 USDC = 500 USDC
// Charlie: 500 YES tokens * 1 USDC = 500 USDC
// LP: 3000 YES tokens * 1 USDC = 3000 USDC
// Bob: 2000 NO tokens * 0 USDC = 0 USDC
```

## Key Differences Between OrderBook and FPMM (both use UMA for resolution):

1. **Liquidity Management**:
   - OrderBook: LPs must actively create and manage orders via CtfExchange
   - FPMM: Liquidity is managed automatically by the AMM formula

2. **Pricing**:
   - OrderBook: Prices are set by order creators
   - FPMM: Prices are calculated automatically based on pool token ratios

3. **Trading Fees**:
   - OrderBook: Fees are determined by the spread between buy/sell orders
   - FPMM: Fixed fee is charged on every trade

4. **Slippage**:
   - OrderBook: Slippage depends on orderbook depth
   - FPMM: Slippage increases with trade size

5. **Risk Management**:
   - OrderBook: LPs can precisely control their positions
   - FPMM: LPs must accept impermanent loss risk

## Advantages of OrderBook:

1. **Better Price Control**:
   - LPs can set exact prices for each order
   - Multiple price levels can be created

2. **Flexible Position Management**:
   - LPs can adjust token amounts at each price level
   - Easy to add or remove liquidity

3. **Suitable for Large Trades**:
   - Less slippage for large trades
   - Large orders can be placed at fixed prices

4. **Transparency**:
   - All orders are publicly visible
   - Users can see market depth

## Disadvantages of OrderBook:

1. **Requires Active Management**:
   - LPs must constantly monitor and adjust orders
   - More effort needed to maintain liquidity

2. **Higher Gas Costs**:
   - Each order requires a transaction
   - Many small orders can incur high gas fees

3. **More Complex**:
   - Users need to understand orderbook mechanics
   - Can be confusing for newcomers

4. **Order Matching Risk**:
   - Orders may not be matched if there are no counterparties
   - Order expiration must be managed 