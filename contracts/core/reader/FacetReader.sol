// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../interfaces/IFacetReader.sol";
import "../../libraries/LibTypeCast.sol";
import "../Mux3FacetBase.sol";
import "../trade/PositionAccount.sol";

contract FacetReader is Mux3FacetBase, PositionAccount, IFacetReader {
    using LibTypeCast for address;
    using LibTypeCast for bytes32;
    using LibTypeCast for uint256;
    using LibConfigMap for mapping(bytes32 => bytes32);
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    /**
     * @dev Get price of token
     */
    function priceOf(address token) external view returns (uint256 price) {
        price = _priceOf(token);
    }

    /**
     * @dev Get price of OracleId
     */
    function priceOf(bytes32 oracleId) external view returns (uint256 price) {
        price = _priceOf(oracleId);
    }

    /**
     * @dev Get core global config
     */
    function configValue(bytes32 key) external view returns (bytes32 value) {
        value = _configs.getBytes32(key);
    }

    /**
     * @dev Get Market config
     */
    function marketConfigValue(bytes32 marketId, bytes32 key) external view returns (bytes32 value) {
        value = _markets[marketId].configs.getBytes32(key);
    }

    /**
     * @dev Get Market state
     */
    function marketState(bytes32 marketId) external view returns (string memory symbol, bool isLong) {
        MarketInfo storage market = _markets[marketId];
        symbol = market.symbol;
        isLong = market.isLong;
    }

    /**
     * @dev Get Collateral config
     */
    function getCollateralToken(address token) external view returns (bool enabled, uint8 decimals) {
        CollateralTokenInfo storage collateralToken = _collateralTokens[token];
        enabled = collateralToken.enabled == Enabled.Enabled;
        decimals = collateralToken.decimals;
    }

    /**
     * @dev List Collateral addresses
     */
    function listCollateralTokens() external view returns (address[] memory tokens) {
        tokens = _collateralTokenList;
    }

    /**
     * @dev Get CollateralPool config
     */
    function getCollateralPool(address pool) public view returns (bool enabled) {
        enabled = _isPoolExist(pool);
    }

    /**
     * @dev List CollateralPool addresses
     */
    function listCollateralPool() external view returns (address[] memory pools) {
        uint256 length = _collateralPoolList.length();
        pools = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            pools[i] = _collateralPoolList.at(i);
        }
    }

    /**
     * @dev List Markets
     */
    function listMarkets() external view returns (bytes32[] memory marketIds) {
        marketIds = _marketList.values();
    }

    /**
     * @dev List backed CollateralPool in a Market
     */
    function listMarketPools(bytes32 marketId) external view returns (BackedPoolState[] memory pools) {
        pools = _markets[marketId].pools;
    }

    /**
     * @dev List PositionIds of a Trader
     */
    function listPositionIdsOf(address trader) external view returns (bytes32[] memory positionIds) {
        positionIds = _positionIdListOf[trader].values();
    }

    /**
     * @dev List active PositionIds
     *
     *      "active" means positionId that likely has positions. positionId with only collateral may not be in this list
     */
    function listActivePositionIds(
        uint256 begin,
        uint256 end
    ) external view returns (bytes32[] memory positionIds, uint256 totalLength) {
        totalLength = _activatePositionIdList.length();
        if (end > totalLength) {
            end = totalLength;
        }
        if (begin > end) {
            begin = end;
        }
        positionIds = new bytes32[](end - begin);
        for (uint256 i = begin; i < end; i++) {
            positionIds[i - begin] = _activatePositionIdList.at(i);
        }
    }

    /**
     * @dev Get Position of (PositionAccount, marketId)
     */
    function getPositionAccount(
        bytes32 positionId,
        bytes32 marketId
    ) public view returns (PositionReader memory position) {
        PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
        position.marketId = marketId;
        position.initialLeverage = positionData.initialLeverage;
        position.lastIncreasedTime = positionData.lastIncreasedTime;
        position.realizedBorrowingUsd = positionData.realizedBorrowingUsd;
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        position.pools = new PositionPoolReader[](backedPools.length);
        for (uint256 j = 0; j < backedPools.length; j++) {
            address backedPool = backedPools[j].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            position.pools[j].poolAddress = backedPool;
            position.pools[j].size = pool.size;
            position.pools[j].entryPrice = pool.entryPrice;
            position.pools[j].entryBorrowing = pool.entryBorrowing;
        }
    }

    /**
     * @dev List Collaterals of a PositionAccount
     */
    function listAccountCollaterals(bytes32 positionId) public view returns (CollateralReader[] memory collaterals) {
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        uint256 length = positionAccount.activeCollaterals.length();
        collaterals = new CollateralReader[](length);
        for (uint256 i = 0; i < length; i++) {
            address collateralToken = positionAccount.activeCollaterals.at(i);
            collaterals[i].collateralAddress = collateralToken;
            collaterals[i].collateralAmount = positionAccount.collaterals[collateralToken];
        }
    }

    /**
     * @dev List Positions of a PositionAccount
     */
    function listAccountPositions(bytes32 positionId) public view returns (PositionReader[] memory positions) {
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        uint256 length = positionAccount.activeMarkets.length();
        positions = new PositionReader[](length);
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = positionAccount.activeMarkets.at(i);
            positions[i] = getPositionAccount(positionId, marketId);
        }
    }

    /**
     * @dev List Collaterals and Positions of all PositionAccounts of a Trader
     */
    function listCollateralsAndPositionsOf(address trader) external view returns (AccountReader[] memory positions) {
        EnumerableSetUpgradeable.Bytes32Set storage positionIds = _positionIdListOf[trader];
        uint256 positionIdCount = positionIds.length();
        positions = new AccountReader[](positionIdCount);
        for (uint256 i = 0; i < positionIdCount; i++) {
            bytes32 positionId = positionIds.at(i);
            positions[i].positionId = positionId;
            positions[i].collaterals = listAccountCollaterals(positionId);
            positions[i].positions = listAccountPositions(positionId);
        }
    }

    /**
     * @dev List active Collaterals and Positions
     *
     *      "active" means positionId that likely has positions. positionId with only collateral may not be in this list
     */
    function listActiveCollateralsAndPositions(
        uint256 begin,
        uint256 end
    ) external view returns (AccountReader[] memory positions, uint256 totalLength) {
        totalLength = _activatePositionIdList.length();
        if (end > totalLength) {
            end = totalLength;
        }
        if (begin > end) {
            begin = end;
        }
        positions = new AccountReader[](end - begin);
        for (uint256 i = begin; i < end; i++) {
            bytes32 positionId = _activatePositionIdList.at(i);
            positions[i - begin].positionId = positionId;
            positions[i - begin].collaterals = listAccountCollaterals(positionId);
            positions[i - begin].positions = listAccountPositions(positionId);
        }
    }

    /**
     * @dev Check if deleverage is allowed
     *
     *      note: you should multicall([
     *              updateBorrowingFee,
     *              isDeleverageAllowed
     *            ])
     */
    function isDeleverageAllowed(bytes32 positionId, bytes32 marketId) external view returns (bool) {
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        require(!_marketDisableTrade(marketId), MarketTradeDisabled(marketId));
        require(_isPositionAccountExist(positionId), PositionAccountNotExists(positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        uint256 tradingPrice = _priceOf(_marketOracleId(marketId));
        // allocation (just copy the existing sizes)
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        PositionData storage positionData = positionAccount.positions[marketId];
        uint256[] memory allocations = new uint256[](backedPools.length);
        for (uint256 i = 0; i < backedPools.length; i++) {
            uint256 sizeForPool = positionData.pools[backedPools[i].backedPool].size;
            allocations[i] = sizeForPool;
        }
        // pnl
        int256[] memory poolPnlUsds = _positionPnlUsd(
            positionId,
            marketId,
            allocations,
            tradingPrice,
            false /* use pnl */
        );
        // return true if any pool satisfies adl condition
        for (uint256 i = 0; i < poolPnlUsds.length; i++) {
            if (poolPnlUsds[i] > 0) {
                bytes32 key = keccak256(abi.encodePacked(MCP_ADL_TRIGGER_RATE, marketId));
                uint256 rate = ICollateralPool(backedPools[i].backedPool).configValue(key).toUint256();
                require(rate > 0, EssentialConfigNotSet("MCP_ADL_TRIGGER_RATE"));
                uint256 entryPrice = positionData.pools[backedPools[i].backedPool].entryPrice;
                uint256 triggerUsd = (allocations[i] * entryPrice) / 1e18;
                triggerUsd = (triggerUsd * rate) / 1e18;
                if (poolPnlUsds[i] > triggerUsd.toInt256()) {
                    return true;
                }
            }
        }
        return false;
    }
}
