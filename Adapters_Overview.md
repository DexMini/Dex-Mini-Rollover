# Protocols & Functions Supported for the Router

## Overview

The foundation of Dex Mini's seamless router contract functionality lies in its **ILiquidityAdapter** contracts. These individual protocol adapters act as standardized interfaces, bridging the gap between the router, Mini AI, and various DeFi protocols. This design abstracts away protocol-specific complexities, making it remarkably easy to integrate support for new protocols and unlock a wider range of DeFi opportunities.

ILiquidityAdapters act as universal connectors, enabling Dex Mini to interface with diverse smart contracts. This standardized approach unlocks crucial actions like cross-protocol interoperability, empowering users to leverage unique features such as multi-token pools and specific parameters (bonding curves, tick ranges, slippage). For developers, this simplifies the creation of intricate DeFi transactions across protocols using simple JavaScript, significantly reducing development time.

## Key Responsibilities of ILiquidityAdapters:

- **Approve Protocol Usage**: Authorize contract interactions for actions like deposits, withdrawals, buys, and sells.
- **Claim Rewards**: Retrieve farming rewards earned within the protocol.
- **Withdraw Liquidity**: Remove liquidity from a source pool.
- **Apply Fees**: Deduct fees for the rollover service, ensuring transparency and sustainability.
- **Deposit Liquidity**: Add liquidity tokens to the protocol's farming contract.
- **Swap**: Execute token swaps within the protocol's ecosystem.
- **Event Emission**: Notify the frontend about critical stages of the process, providing real-time feedback to users.

## Supported Adapters and Use Cases

### Frax Ether Adapter
- **Purpose**: Facilitates liquidity migration for Frax Ether (frxETH), a liquid staking derivative for Ethereum.
- **Use Cases**: Migrate frxETH liquidity between pools or protocols, support concentrated liquidity management in Uniswap V3, enable staking rewards.

### mETH Protocol Adapter
- **Purpose**: Handles mETH, a liquid staking token from Meta Pool or similar protocols.
- **Use Cases**: Migrate mETH liquidity across protocols, enable impermanent loss protection.

### Uniswap v2 Adapter
- **Purpose**: Supports liquidity migration for Uniswap V2 pools.
- **Use Cases**: Migrate LP tokens, claim rewards from farming contracts.

### Uniswap v3 Adapter
- **Purpose**: Enables concentrated liquidity management for Uniswap V3 pools.
- **Use Cases**: Migrate liquidity within tick ranges, stake LP tokens, optimize capital efficiency.

### Curve Adapter
- **Purpose**: Facilitates liquidity migration for Curve pools.
- **Use Cases**: Migrate liquidity between Curve pools, claim CRV rewards, stake LP tokens.

### Aerodrome Adapter
- **Purpose**: Supports Aerodrome, a fork of Velodrome optimized for Base chain.
- **Use Cases**: Migrate liquidity between Aerodrome pools, claim rewards, stake LP tokens.

### Balancer Adapter
- **Purpose**: Handles liquidity migration for Balancer pools.
- **Use Cases**: Migrate liquidity, stake BPTs in farming contracts.

### Velodrome Adapter
- **Purpose**: Facilitates liquidity migration for Velodrome.
- **Use Cases**: Migrate liquidity, claim rewards, stake LP tokens.

### Bancor Adapter
- **Purpose**: Supports Bancor’s single-sided exposure and impermanent loss protection.
- **Use Cases**: Maintain IL protection, claim BNT rewards, stake LP tokens.

### Pendle Adapter
- **Purpose**: Facilitates liquidity migration for Pendle, a protocol for tokenized yield.
- **Use Cases**: Migrate YT (Yield Tokens) and PT (Principal Tokens), stake tokens.

### PancakeSwap Adapter
- **Purpose**: Supports liquidity migration for PancakeSwap on BNB Chain.
- **Use Cases**: Migrate LP tokens, claim CAKE rewards, stake LP tokens.

### Camelot Adapter
- **Purpose**: Facilitates liquidity migration for Camelot on Arbitrum.
- **Use Cases**: Migrate liquidity, claim GRAIL rewards, stake LP tokens.

### Uniswap V4 Adapter
- **Purpose**: Supports Uniswap V4, introducing hooks and custom pool logic.
- **Use Cases**: Migrate liquidity with custom hooks, stake LP tokens.

### Lido Adapter
- **Purpose**: Supports stETH, a liquid staking token from Lido.
- **Use Cases**: Migrate stETH liquidity, stake stETH in Curve.

### AAVE V3 Adapter
- **Purpose**: Facilitates liquidity migration for AAVE V3 lending pools.
- **Use Cases**: Supply/withdraw assets, stake aTokens.

### Rocket Pool Adapter
- **Purpose**: Handles rETH, a liquid staking token from Rocket Pool.
- **Use Cases**: Migrate rETH liquidity, stake rETH.

### Kelp Adapter
- **Purpose**: Supports Kelp DAO’s restaking mechanisms.
- **Use Cases**: Migrate restaked ETH liquidity, claim rewards.

### MakerDAO Adapter
- **Purpose**: Facilitates liquidity migration for MakerDAO’s DAI and collateral pools.
- **Use Cases**: Supply/withdraw collateral, stake DAI.

### Morpho Blue Adapter
- **Purpose**: Supports Morpho’s peer-to-peer lending protocol.
- **Use Cases**: Supply/borrow assets, manage positions.

### Sushi Adapter
- **Purpose**: Supports the SushiSwap DEX and related features.
- **Use Cases**: Swap tokens, provide liquidity, stake SUSHI, claim rewards.

### Euler Adapter
- **Purpose**: Enables interaction with the Euler Finance lending protocol.
- **Use Cases**: Supply/borrow assets, manage positions.

### Convex Finance Adapter
- **Purpose**: Supports CVX and CRV rewards from Convex.
- **Use Cases**: Stake LP tokens, claim rewards.

### GMX - GLV Vault Adapter
- **Purpose**: Facilitates liquidity migration for GMX’s GLV Vault.
- **Use Cases**: Stake GMX tokens, claim rewards.

### Ondo Finance Adapter
- **Purpose**: Supports Ondo Finance’s tokenized real-world assets.
- **Use Cases**: Interact with tokenized assets.

### ZeroEx Adapter
- **Purpose**: Enables execution of swaps using 0x Protocol.
- **Use Cases**: Route token swaps efficiently, leverage on-chain liquidity aggregation.

## Conclusion

Dex Mini’s **ILiquidityAdapter** system provides a scalable, modular framework for liquidity migration across multiple DeFi protocols. By abstracting the complexity of individual smart contracts, developers can integrate new protocols seamlessly, while users benefit from effortless cross-chain and cross-protocol liquidity management. With an ever-growing ecosystem of adapters, Dex Mini continues to push the boundaries of decentralized finance, unlocking new opportunities for DeFi participants worldwide.

