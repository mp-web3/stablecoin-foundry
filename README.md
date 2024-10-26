# Stablecoin Foundry

## Resources

### **Aave** Liquidation, Health Factor and Risk Paramenters

- [Aave Protocol Parameter Dashboard](https://aave.com/docs/resources/parameters)
- [Aave Health Factor Simulation Tool](https://defisim.xyz/)
- [Aave Liquidation dev docs](https://aave.com/docs/concepts/liquidations)
- [DeFi Saver](https://defisaver.com/)
  > DeFi Saver is a non-custodial DeFi management tool offering advanced features and functionalities for managing your positions and crypto assets in various DeFi protocols
- [Liquidations/Liquidator dev docs](https://aave.com/docs/developers/liquidations#calculating-profitability-vs-gas-cost)

## Our Stablecoin Features

1. Relative Stability: Anchored/Pegged to $
2. Stability Mechanism (Minting and Burning): Algorithmic (fully decentralized)
3. Collateral: Exogenous (Crypto)
   - ETH
   - BTC

---

## Implementation specs

### Relative Stability (Pegged)

We'll maintain relative stability through [Chainlink Price Feeds](https://docs.chain.link/data-feeds/price-feeds)
We'll set a function to exchange ETH & BTC for $$$

### Stability Mechanism (Algorithmic)

Can only mint the stablecoin with enough collateral (overcollateralized)

### Collateral (Exogenous)

- wETH
- wBTC

---

## Libs

### openzeppelin

`openzeppelin-contracts`

```
forge install openzeppelin/openzeppelin-contracts --no-commit
```

### smartcontractkit/chainlink

`chainlink-brownie-contracts@0.6.1`

```
forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit
```

---

## Liquidation, Health Factor and Risk Paramenters

- [Aave Protocol Parameter Dashboard](https://aave.com/docs/resources/parameters)
- [Aave Health Factor Simulation Tool](https://defisim.xyz/)
- [Aave Liquidation dev docs](https://aave.com/docs/concepts/liquidations)
- [DeFi Saver](https://defisaver.com/)
  > DeFi Saver is a non-custodial DeFi management tool offering advanced features and functionalities for managing your positions and crypto assets in various DeFi protocols
- [Liquidations/Liquidator dev docs](https://aave.com/docs/developers/liquidations#calculating-profitability-vs-gas-cost)
