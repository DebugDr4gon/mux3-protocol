// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "../../interfaces/IFacetReader.sol";
import "../../libraries/LibTypeCast.sol";
import "../Mux3FacetBase.sol";

contract FacetReader is Mux3FacetBase, IFacetReader {
    using LibTypeCast for address;
    using LibConfigTable for ConfigTable;
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
    )
        external
        view
        returns (
            string memory symbol,
            bool isLong,
            uint256 cumulatedBorrowingPerUsd,
            uint256 lastBorrowingFeeUpdateTime
        )
    {
        MarketInfo storage market = _markets[marketId];
        return (
            market.symbol,
            market.isLong,
            market.cumulatedBorrowingPerUsd,
            market.lastBorrowingFeeUpdateTime
        );
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
    )
        public
        view
        returns (
            address[] memory collateralAddresses,
            uint256[] memory collateralAmounts
        )
    {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        uint256 length = positionAccount.activeCollaterals.length();
        collateralAddresses = new address[](length);
        collateralAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            address collateralToken = positionAccount.activeCollaterals.at(i);
            collateralAddresses[i] = collateralToken;
            collateralAmounts[i] = _positionAccounts[positionId].collaterals[
                collateralToken
            ];
        }
    }

    function listAccountPositions(
        bytes32 positionId
    )
        public
        view
        returns (bytes32[] memory marketIds, PositionData[] memory positions)
    {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        uint256 length = positionAccount.activeMarkets.length();
        marketIds = new bytes32[](length);
        positions = new PositionData[](length);
        for (uint256 i = 0; i < length; i++) {
            marketIds[i] = positionAccount.activeMarkets.at(i);
            positions[i] = positionAccount.positions[marketIds[i]];
        }
    }

    function listAccountCollateralsAndPositionsOf(
        address trader
    )
        external
        view
        returns (AccountCollateralsAndPositions[] memory positions)
    {
        EnumerableSetUpgradeable.Bytes32Set
            storage positionIds = _positionAccountLists[trader];
        uint256 positionIdCount = positionIds.length();
        positions = new AccountCollateralsAndPositions[](positionIdCount);
        for (uint256 i = 0; i < positionIdCount; i++) {
            bytes32 positionId = positionIds.at(i);
            positions[i].positionId = positionId;
            (
                positions[i].collateralAddresses,
                positions[i].collateralAmounts
            ) = listAccountCollaterals(positionId);
            (
                positions[i].marketIds,
                positions[i].positions
            ) = listAccountPositions(positionId);
        }
    }
}
