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
- Each price feed includes `maxAge`, measured in seconds. Borrowing and liquidation reject non-positive prices, missing or future timestamps, and updates older than that limit. Set the limit for the selected feed's heartbeat and expected update delay; the deployment helper uses 25 hours for GBP/USD and 2 hours for WETH/USD.
- Deposits credit the collateral actually received. Incoming transfer fees reduce borrowing capacity. Collateral must have fixed balances and 6–18 decimals. Outgoing transfers must debit the vault and credit the recipient by exactly the quoted amount; recipient fees, additional vault-side fees, and rebasing are unsupported. Governance must verify this behavior before listing collateral; deployment cannot detect every token's transfer behavior. Feed decimals must match the configured value and cannot exceed 18.
- Both price conversions retain 18-decimal price precision. Minimum collateral previews round up; payouts round down.

### Liquidation

- Vaults have liquidation thresholds and close factors that determine borrowing capacity and liquidation scenarios.
- A liquidator can pay a portion of the debt and receive collateral, including a liquidation spread.
- The configured spread is a maximum bonus. For positions whose collateral still covers their debt, the bonus is capped at their surplus so liquidation does not make them insolvent. Safe risk parameters require `liquidationThreshold * (100 + liquidationSpread) < 10000`.
- Positions at or below the health factor implied by that threshold and spread allow repayment of the full debt, overriding the normal close factor. Use `previewLiquidation(account, maxGbpcToRepay)` for the actual repayment and collateral payout; the older `previewLiquidate(amount)` is an uncapped estimate only.
- The caller's repayment ceiling is capped at the allowed close factor and debt. Very small positions or unusually valuable indivisible token units can still have a payout below one collateral unit; such a liquidation reverts rather than paying an excessive bonus. The supported decimal range excludes whole-token collateral, but does not guarantee liquidation of every dust position. Governance must consider atomic-unit value and liquidation transaction costs when listing collateral.
- A price gap can make collateral worth less than the debt before a liquidator acts. When liquidation consumes all collateral, remaining unpaid debt moves to the vault's `badDebt()` balance and emits `BadDebtRecorded`. Liquidation burns only the recoverable amount, up to the caller's maximum. Anyone can approve the vault and call `coverBadDebt(amount)` to burn their GBPC against this shortfall. The vault does not charge other depositors or draw on another vault's collateral.

### Governance and deployment compatibility

- These contracts are not upgradeable. The fixes require a new deployment and a separate migration plan for existing positions. `VaultMaster` construction and `deployVault` require a price-age limit; `USDPriceFeed` now contains `(feed, decimals, maxAge)`. Update proposal calldata to the new signatures.
- Oracle validation follows the [Chainlink data-feed interface](https://docs.chain.link/data-feeds/api-reference).

## Usage

### Build

Initialize the pinned dependencies, including the nested test dependency:

```shell
git submodule update --init
git -C lib/forge-std submodule update --init lib/ds-test
```

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
