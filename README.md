# Stablecoin Foundry

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

`openzeppelin-contracts`

```
forge install openzeppelin/openzeppelin-contracts --no-commit
```

---

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
