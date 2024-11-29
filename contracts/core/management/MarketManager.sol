// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "../Mux3FacetBase.sol";

contract MarketManager is Mux3FacetBase {
    using LibConfigMap for mapping(bytes32 => bytes32);
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _createMarket(bytes32 marketId, string memory symbol, bool isLong) internal {
        require(marketId != bytes32(0), InvalidMarketId(marketId));
        require(!_isMarketExist(marketId), MarketAlreadyExist(marketId));
        // create market
        _markets[marketId].symbol = symbol;
        _markets[marketId].isLong = isLong;
        require(_marketList.length() < MAX_MARKETS, CapacityExceeded(MAX_MARKETS, _marketList.length(), 1));
        require(_marketList.add(marketId), ArrayAppendFailed());
    }

    function _appendBackedPoolsToMarket(bytes32 marketId, address[] memory backedPools) internal {
        require(_isMarketExist(marketId), MarketNotExists(marketId));
        require(backedPools.length > 0, InvalidArrayLength(backedPools.length, 0));
        uint256 count = backedPools.length;
        MarketInfo storage market = _markets[marketId];
        require(
            market.pools.length + count <= MAX_MARKET_BACKED_POOLS,
            CapacityExceeded(MAX_MARKET_BACKED_POOLS, market.pools.length, count)
        );
        for (uint256 i = 0; i < count; i++) {
            address newBackedPool = backedPools[i];
            require(_isPoolExist(newBackedPool), PoolNotExists(newBackedPool));
            // this pool is not one of the existing backed pools
            for (uint256 j = 0; j < market.pools.length; j++) {
                require(market.pools[j].backedPool != newBackedPool, PoolAlreadyExist(newBackedPool));
            }
            market.pools.push(BackedPoolState({ backedPool: newBackedPool }));
            ICollateralPool(newBackedPool).setMarket(marketId, market.isLong);
        }
    }

    function _setMarketConfig(bytes32 marketId, bytes32 key, bytes32 value) internal {
        require(_isMarketExist(marketId), MarketNotExists(marketId));
        _markets[marketId].configs.setBytes32(key, value);
    }
}
