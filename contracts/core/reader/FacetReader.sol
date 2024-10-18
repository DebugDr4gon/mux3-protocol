// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../interfaces/IFacetReader.sol";
import "../../libraries/LibTypeCast.sol";
import "../Mux3FacetBase.sol";

contract FacetReader is Mux3FacetBase, IFacetReader {
    using LibTypeCast for address;
    using LibConfigMap for mapping(bytes32 => bytes32);
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function priceOf(address token) external view returns (uint256) {
        return _priceOf(token);
    }

    function priceOf(bytes32 id) external view returns (uint256) {
        return _priceOf(id);
    }

    function configValue(bytes32 key) external view returns (bytes32) {
        return _configs.getBytes32(key);
    }

    function marketConfigValue(
        bytes32 marketId,
        bytes32 key
    ) external view returns (bytes32) {
        return _markets[marketId].configs.getBytes32(key);
    }

    function marketState(
        bytes32 marketId
    ) external view returns (string memory symbol, bool isLong) {
        MarketInfo storage market = _markets[marketId];
        return (market.symbol, market.isLong);
    }

    function getCollateralToken(
        address token
    ) external view returns (bool enabled, uint8 decimals) {
        CollateralTokenInfo storage collateralToken = _collateralTokens[token];
        enabled = collateralToken.enabled == Enabled.Enabled;
        decimals = collateralToken.decimals;
    }

    function getCollateralPool(
        address pool
    ) public view returns (bool enabled) {
        enabled = _isPoolExist(pool);
    }

    function listCollateralPool() external view returns (address[] memory) {
        address[] memory pools = new address[](_collateralPoolList.length());
        for (uint256 i = 0; i < _collateralPoolList.length(); i++) {
            pools[i] = _collateralPoolList.at(i);
        }
        return pools;
    }

    function listMarkets() external view returns (bytes32[] memory) {
        return _marketList.values();
    }

    function listMarketPools(
        bytes32 marketId
    ) external view returns (BackedPoolState[] memory) {
        return _markets[marketId].pools;
    }

    function listPositionIdsOf(
        address trader
    ) external view returns (bytes32[] memory) {
        return _positionAccountLists[trader].values();
    }

    function listAccountCollaterals(
        bytes32 positionId
    ) public view returns (CollateralReader[] memory collaterals) {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        uint256 length = positionAccount.activeCollaterals.length();
        collaterals = new CollateralReader[](length);
        for (uint256 i = 0; i < length; i++) {
            address collateralToken = positionAccount.activeCollaterals.at(i);
            collaterals[i].collateralAddress = collateralToken;
            collaterals[i].collateralAmount = positionAccount.collaterals[
                collateralToken
            ];
        }
    }

    function listAccountPositions(
        bytes32 positionId
    ) public view returns (PositionReader[] memory positions) {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        uint256 length = positionAccount.activeMarkets.length();
        positions = new PositionReader[](length);
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = positionAccount.activeMarkets.at(i);
            PositionData storage positionData = positionAccount.positions[
                marketId
            ];
            positions[i].marketId = marketId;
            positions[i].initialLeverage = positionData.initialLeverage;
            positions[i].lastIncreasedTime = positionData.lastIncreasedTime;
            positions[i].realizedBorrowingUsd = positionData
                .realizedBorrowingUsd;
            BackedPoolState[] storage backedPools = _markets[marketId].pools;
            positions[i].pools = new PositionPoolReader[](backedPools.length);
            for (uint256 j = 0; j < backedPools.length; j++) {
                address backedPool = backedPools[j].backedPool;
                PositionPoolData memory pool = positionData.pools[backedPool];
                positions[i].pools[j].poolAddress = backedPool;
                positions[i].pools[j].size = pool.size;
                positions[i].pools[j].entryPrice = pool.entryPrice;
                positions[i].pools[j].entryBorrowing = pool.entryBorrowing;
            }
        }
    }

    function listAccountCollateralsAndPositionsOf(
        address trader
    ) external view returns (AccountReader[] memory positions) {
        EnumerableSetUpgradeable.Bytes32Set
            storage positionIds = _positionAccountLists[trader];
        uint256 positionIdCount = positionIds.length();
        positions = new AccountReader[](positionIdCount);
        for (uint256 i = 0; i < positionIdCount; i++) {
            bytes32 positionId = positionIds.at(i);
            positions[i].positionId = positionId;
            positions[i].collaterals = listAccountCollaterals(positionId);
            positions[i].positions = listAccountPositions(positionId);
        }
    }
}
