# mux3-protocol

MUX3 Protocol is an advanced margin trading protocol that enables traders to maintain positions using cross-margin strategies while enhancing capital efficiency for liquidity providers (LPs).

Traders can use multiple collateral tokens to maintain their positions, providing greater flexibility in risk management.

Unlike traditional protocols, MUX3 splits backed Collateral Pool into multiple Pools, allowing LPs to provide single-token liquidity and better control their asset exposure.

## Protocol Structure

The protocol primarily consists of the `Mux3` and the `OrderBook`. When an `Order` is placed on the `OrderBook`, off-chain `Broker` query the dark `Oracle` to get `marketPrice` and call `OrderBook` to fill the order. The `OrderBook` contract communicates with the `Mux3` to execute the trade.

The `Mux3` uses a Diamond proxy pattern with multiple facets handling different aspects of functionality including `FacetOpen`, `FacetClose`, `FacetPositionAccount`, `FacetManagement`, `FacetReader`.

### Development

In order to run the unit tests, you probably need to open hardhat.config.ts and modify `optimizerSteps` to `"u"`.
