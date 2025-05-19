# FixedProductMarketMaker (FPMM) Prediction Market Simulation with UMA Oracle

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

## 2. LP Provides Liquidity to FPMM

```javascript
// LP approves USDC for FPMM
await usdc.approve(fpmm.address, "10000000000"); // 10,000 USDC

// LP adds liquidity to FPMM
await fpmm.addFunding(
    10000000000,             // 10,000 USDC
    [1, 1]                   // 50/50 distribution YES/NO
);
// LP receives LP tokens representing pool ownership
```

## 3. Users Buy/Sell Outcome Tokens via FPMM

```javascript
// Alice buys 1000 YES tokens via FPMM
await fpmm.buy(
    550000000,               // Invest 550 USDC
    0,                       // outcomeIndex = 0 (YES)
    900                      // minOutcomeTokensToBuy (slippage protection)
);
// Alice receives ~1000 YES tokens, FPMM automatically calculates price and fee

// Bob sells 500 NO tokens via FPMM
await fpmm.sell(
    250000000,               // Wants to receive 250 USDC
    1,                       // outcomeIndex = 1 (NO)
    600                      // maxOutcomeTokensToSell (slippage protection)
);
// Bob sends 500 NO tokens, receives 250 USDC, FPMM automatically calculates price and fee
```

## 4. Market Resolution via UMA Oracle

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
```

## 5. Redeem and Withdraw Liquidity

```javascript
// YES token holders redeem USDC
await conditionalTokens.redeemPositions(
    usdc.address,
    marketId,
    conditionId,
    [1, 0] // Only redeem YES tokens
);

// LP withdraws liquidity from FPMM
await fpmm.removeFunding(
    lpTokenAmount // Amount of LP tokens to burn
);
```

## Comparison: FPMM vs OrderBook

- **FPMM**: Continuous liquidity, price is set automatically by AMM formula, LPs earn trading fees, no need to manage orders, but there is impermanent loss risk.
- **OrderBook**: LPs actively place orders, better price control, suitable for large trades, no impermanent loss but requires active order management. 