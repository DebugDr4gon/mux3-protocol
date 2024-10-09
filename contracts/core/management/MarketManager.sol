// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "../../interfaces/IMarket.sol";
import "../Mux3FacetBase.sol";

contract MarketManager is Mux3FacetBase {
    using LibConfigTable for ConfigTable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _createMarket(
        bytes32 marketId,
        string memory symbol,
        bool isLong
    ) internal {
        require(marketId != bytes32(0), InvalidMarketId(marketId));
        require(!_isMarketExists(marketId), MarketAlreadyExists(marketId));
        // create market
        _markets[marketId].symbol = symbol;
        _markets[marketId].isLong = isLong;
        require(_marketList.add(marketId), ArrayAppendFailed());
    }

    function _appendBackedPoolsToMarket(
        bytes32 marketId,
        address[] memory backedPools
    ) internal {
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        require(
            backedPools.length > 0,
            InvalidArrayLength(backedPools.length, 0)
        );
        uint256 count = backedPools.length;
        MarketInfo storage market = _markets[marketId];
        for (uint256 i = 0; i < count; i++) {
            address newBackedPool = backedPools[i];
            require(_isPoolExist(newBackedPool), PoolNotExists(newBackedPool));
            // this pool is not one of the existing backed pools
            for (uint256 j = 0; j < market.pools.length; j++) {
                require(
                    market.pools[j].backedPool != newBackedPool,
                    PoolAlreadyExist(newBackedPool)
                );
            }
            market.pools.push(
                BackedPoolState({
                    backedPool: newBackedPool,
                    totalSize: 0,
                    unpaidBorrowingFeeUsd: 0
                })
            );
            ICollateralPool(newBackedPool).setMarket(marketId, market.isLong);
        }
    }

    function _setMarketConfig(
        bytes32 marketId,
        bytes32 key,
        bytes32 value
    ) internal {
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        _markets[marketId].configs.setBytes32(key, value);
    }
}
