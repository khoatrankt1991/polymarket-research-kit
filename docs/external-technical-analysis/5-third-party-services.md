# Third-party Services/Platforms Used by Polymarket

## 1. TheGraph
**Repo: polymarket-subgraph**
* The entire repository is for configuring and deploying subgraphs
* Multiple different subgraphs: fpmm-subgraph, activity-subgraph, oi-subgraph, orderbook-subgraph, pnl-subgraph

**Repo: redis-leaderboard**
* File: `/src/getLeaderboardData.ts`
* GraphQL Endpoint: https://api.thegraph.com/subgraphs/name/tokenunion/polymarket-matic

## 2. UMA Protocol (Optimistic Oracle)
**Repo: uma-ctf-adapter**
* UMA Oracle integration for market resolution

**Repo: uma-binary-adapter-sdk**
* SDK for UMA integration

**Repo: uma-sports-oracle**
* Oracle deployment for sports markets

## 3. Polygon (Matic)
**Repo: Multiple repositories**
* Smart contracts deployed on Polygon blockchain
* Example: matic-withdrawal-batcher, polymarket-subgraph

**Repo: poly-ct-scripts**
* File: `/.env.example`
* References to SENDER and RPC endpoints

## 4. IPFS
**Repo: routing-api**
* File: `/bin/stacks/routing-caching-stack.ts`
* Reference to ipfsPoolCachingLambda

**Repo: s3x**
* Integration between S3 and IPFS

## 5. Pinata (IPFS Pinning Service)
**Repo: routing-api**
* File: `/bin/stacks/routing-api-stack.ts`
* Env vars: pinata_key and pinata_secret

## 6. Gnosis Safe & Conditional Tokens
**Repo: conditional-tokens-contracts**
* Smart contracts for conditional tokens (fork from Gnosis)

**Repo: conditional-tokens-market-makers**
* Market maker implementation for conditional tokens

## 7. Tenderly (Blockchain Simulation Platform)
**Repo: routing-api**
* File: `/bin/stacks/routing-api-stack.ts`
* Environment variables:
  * tenderlyUser: string
  * tenderlyProject: string
  * tenderlyAccessKey: string

## 8. Infura (RPC Provider)
**Repo: relayer-deposits**
* File: `/.env.example`
* INFURA_API_KEY=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz

**Repo: Multiple other repositories** with references to Infura
* Used as Web3 provider

## 9. Aiven (Managed Redis)
**Repo: redis-leaderboard**
* File: `/src/server.ts`
* Connection string:
* rediss://default:ognm4av69h62s0jc@redis-27db2bc3-polymarket-d1ee.aivencloud.com:12790

## 10. OpenZeppelin Defender
**Repo: relayer-deposits**
* File: `/packages/server/src/defender.ts`
* File: `/.env.example`
* DEFENDER_CREDENTIALS={"apiKey": "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", "apiSecret": "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"}

## 11. ETH Gas Station
**Repo: routing-api**
* File: `/bin/stacks/routing-api-stack.ts`
* ethGasStationInfoUrl: string

## 12. Uniswap Smart Order Router (Fork or Integration)
**Repo: routing-api**
* File: `/bin/stacks/routing-api-stack.ts`
* Import:
  * import { SUPPORTED_CHAINS } from '@uniswap/smart-order-router'
  * import { ChainId } from '@uniswap/sdk-core'

## 13. Goldsky (TheGraph Hosting Alternative)
**Repo: polymarket-subgraph**
* File: `/README.md`
* Deployment reference:
* goldsky subgraph deploy <subgraph-name>/<version> --path ./build/

## 14. Chainlink (implied)
**Repo: Indirectly referenced in smart contracts and oracle implementations**
* Possibly used for data feeds and oracle services

## 15. Livepeer
**Repo: livepeerjs**
* Integration for streaming or video services

## 16. Multisig Wallets and Security
**Repo: proxy-factories**
* Deployment of proxy contracts and multisig wallets

## 17. EtherScan/PolygonScan
**Repo: Referenced in multiple repositories for contract verification**

## 18. Apollo Client (GraphQL Client)
**Repo: redis-leaderboard**
* File: `/src/getLeaderboardData.ts`
* Used to query TheGraph

## 19. Hardhat (Development Environment)
**Repo: routing-api**
* File: `/hardhat.config.js`
* Development and testing framework

## 20. Docker and Container Services
**Repo: polymarket-subgraph**
* File: `/docker-compose.yml`
* Container environment for running graph-node

## 21. NewsAPI
**Repo: agents**
* File: `/.env.example`
* NEWSAPI_API_KEY=""

## 22. OpenAI API
**Repo: agents**
* File: `/.env.example`
* OPENAI_API_KEY=""

## 23. Tavily API
**Repo: agents**
* File: `/.env.example`
* TAVILY_API_KEY=""

## 24. Alchemy (RPC Provider)
**Repo: polymarket-subgraph**
* File: `/README.md`
* Mentions Alchemy as a common provider
