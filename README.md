# Great British Pound (GBP) Stablecoin System

## Overview

The Great British Pound (GBP) Stablecoin System is a decentralized finance ecosystem with distinct components that work together to create and manage a stablecoin (GBP Coin), collateralized by various assets, and governed by a decentralized autonomous organization (GreatDAO). Here, we provide an overview of each component:

## System Components

### 1. GBP Coin (GBPC)

GBPC is the stablecoin at the heart of the system. It is designed to maintain a stable value equivalent to one British Pound (GBP). GBPC serves as a reliable medium of exchange and store of value within the ecosystem.

### 2. VaultMaster

VaultMaster is responsible for creating and managing Vaults (Great Vaults) and is owned by the GreatDAO's timelock. Vaults are proposed, voted upon, and executed through the DAO's governance process. It is the only admin of the GBPC and grants the deployed vault a GBPC minter role, and transfers the vault's ownership to the DAO's timelock.

### 3. Great Vault

Great Vaults are created by the VaultMaster. To create a Vault, a proposal, voting, and execution from the GreatDAO are required. Key parameters for Vault creation include collateral (ERC20), USD price feed, liquidation threshold, liquidation spread, and close factor. They are the only contracts that can mint or burn GBPC.

### 4. Great DAO

GreatDAO is the decentralized autonomous organization that governs the entire ecosystem. It has ownership control over the VaultMaster through its timelock and can adjust parameters in Vaults, ensuring proper governance.

### 5. Great Timelock

The Great Timelock manages the timelock functionality for the GreatDAO. It plays a crucial role in time-locked actions and governance proposals.

### 6. Great Coin (GRC Token)

Great Coin (GRC) is the governance token of the GreatDAO. It provides voting power for making decisions within the DAO.

## Functionality

### Collateralization and Minting

- Vaults handle collateralization logic and the minting of GBPC.
- Chainlink price feeds are used to calculate collateral value in GBPC.

### Liquidation

- Vaults have liquidation thresholds and close factors that determine borrowing capacity and liquidation scenarios.
- A liquidator can pay a portion of the debt and receive collateral, including a liquidation spread.

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Anvil

```shell
anvil
```

### Deploy

```shell
forge script script/DeployGBPCSystem.s.sol:DeployGBPCSystem --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
cast <subcommand>
```

### Help

```shell
forge --help
anvil --help
cast --help
```
