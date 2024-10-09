// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

interface IManagement {
    event AddCollateralToken(address token, uint8 decimals);
    event CreateCollateralPool(
        string name,
        string symbol,
        address collateral,
        uint8 collateralDecimals,
        address pool
    );
    event AppendBackedPoolsToMarket(bytes32 marketId, address[] backedPools);
    event SetCollateralPoolImplementation(address newImplementation);
    event CreateMarket(
        bytes32 marketId,
        string symbol,
        bool isLong,
        address[] backedPools
    );
    event SetConfig(bytes32 key, bytes32 value);
    event SetMarketConfig(bytes32 marketId, bytes32 key, bytes32 value);
    event SetCollateralPoolConfig(address pool, bytes32 key, bytes32 value);
    event SetCollateralTokenEnabled(address token, bool enabled);
    event SetOracleProvider(address oracleProvider, bool isValid);
}
