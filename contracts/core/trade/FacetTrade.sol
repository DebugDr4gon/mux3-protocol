// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../../libraries/LibTypeCast.sol";
import "../Mux3FacetBase.sol";
import "./PositionAccount.sol";
import "./Market.sol";

contract FacetTrade is Mux3FacetBase, PositionAccount, Market, ITrade {
    using LibTypeCast for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using LibConfigMap for mapping(bytes32 => bytes32);

    function openPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        address lastConsumedToken
    )
        external
        onlyRole(ORDER_BOOK_ROLE)
        returns (uint256 tradingPrice, uint256 borrowingFeeUsd, uint256 positionFeeUsd)
    {
        require(size % _marketLotSize(marketId) == 0, InvalidPositionSize(size));
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        // TODO: ASSET_IS_TRADABLE
        // TODO: ASSET_IS_OPENABLE
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        tradingPrice = _priceOf(_marketOracleId(marketId));
        uint256[] memory allocations = _allocateLiquidity(marketId, size);
        // update borrowing fee for the current market
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(marketId);
        borrowingFeeUsd = _updateAndDispatchBorrowingFeeForTrade(
            positionAccount.owner,
            positionId,
            marketId,
            cumulatedBorrowingPerUsd,
            true, // shouldCollateralSufficient
            lastConsumedToken
        );
        // position fee
        positionFeeUsd = _dispatchPositionFee(
            positionAccount.owner,
            positionId,
            marketId,
            size,
            allocations,
            false, // isLiquidating
            true, // shouldCollateralSufficient
            lastConsumedToken
        );
        // open position
        _openMarketPosition(marketId, allocations);
        _openAccountPosition(positionId, marketId, allocations, cumulatedBorrowingPerUsd);
        // exceeds leverage set by setInitialLeverage
        require(_isLeverageSafe(positionId), UnsafePositionAccount(positionId, SAFE_LEVERAGE));
        // exceeds leverage set by MM_INITIAL_MARGIN_RATE
        require(_isInitialMarginSafe(positionId), UnsafePositionAccount(positionId, SAFE_INITITAL_MARGIN));
        // done
        {
            (
                address[] memory backedPools,
                uint256[] memory newSizes,
                uint256[] memory newEntryPrices,
                address[] memory newCollateralTokens,
                uint256[] memory newCollateralAmounts
            ) = _dumpForTradeEvent(positionId, marketId);
            emit OpenPosition(
                positionAccount.owner,
                positionId,
                marketId,
                _markets[marketId].isLong,
                size,
                tradingPrice,
                backedPools,
                allocations,
                newSizes,
                newEntryPrices,
                positionFeeUsd,
                borrowingFeeUsd,
                newCollateralTokens,
                newCollateralAmounts
            );
        }
    }

    function closePosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        address lastConsumedToken
    )
        external
        onlyRole(ORDER_BOOK_ROLE)
        returns (uint256 tradingPrice, int256[] memory poolPnlUsds, uint256 borrowingFeeUsd, uint256 positionFeeUsd)
    {
        require(size % _marketLotSize(marketId) == 0, InvalidPositionSize(size));
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        // TODO: ASSET_IS_TRADABLE
        require(_isPositionAccountExist(positionId), PositionAccountNotExists(positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        tradingPrice = _priceOf(_marketOracleId(marketId));
        // allocation
        uint256[] memory allocations = _deallocateLiquidity(positionId, marketId, size);
        // update borrowing fee for the current market
        // borrowing fee should be updated before pnl, because profit/loss will affect aum
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(marketId);
        // pnl
        poolPnlUsds = _positionPnlUsd(positionId, marketId, allocations, tradingPrice);
        poolPnlUsds = _realizeProfitAndLoss(
            positionId,
            marketId,
            poolPnlUsds,
            true, // isThrowBankrupt
            lastConsumedToken
        );
        // update borrowing fee
        borrowingFeeUsd = _updateAndDispatchBorrowingFeeForTrade(
            positionAccount.owner,
            positionId,
            marketId,
            cumulatedBorrowingPerUsd,
            false, // shouldCollateralSufficient
            lastConsumedToken
        );
        // position fee
        positionFeeUsd = _dispatchPositionFee(
            positionAccount.owner,
            positionId,
            marketId,
            size,
            allocations,
            false, // isLiquidating
            false, // shouldCollateralSufficient
            lastConsumedToken
        );
        // close position
        _closeMarketPosition(positionId, marketId, allocations);
        _closeAccountPosition(positionId, marketId, allocations);
        // should safe
        require(
            _isMaintenanceMarginSafe(
                positionId,
                0 // pendingBorrowingFeeUsd = 0 because we have already deducted borrowing fee from collaterals
            ),
            UnsafePositionAccount(positionId, SAFE_MAINTENANCE_MARGIN)
        );
        // done
        {
            (
                address[] memory backedPools,
                uint256[] memory newSizes,
                uint256[] memory newEntryPrices,
                address[] memory newCollateralTokens,
                uint256[] memory newCollateralAmounts
            ) = _dumpForTradeEvent(positionId, marketId);
            emit ClosePosition(
                positionAccount.owner,
                positionId,
                marketId,
                _markets[marketId].isLong,
                size,
                tradingPrice,
                backedPools,
                allocations,
                newSizes,
                newEntryPrices,
                poolPnlUsds,
                positionFeeUsd,
                borrowingFeeUsd,
                newCollateralTokens,
                newCollateralAmounts
            );
        }
    }

    function liquidatePosition(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken
    )
        external
        onlyRole(ORDER_BOOK_ROLE)
        returns (uint256 tradingPrice, int256[] memory poolPnlUsds, uint256 borrowingFeeUsd, uint256 positionFeeUsd)
    {
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        // TODO: ASSET_IS_TRADABLE
        require(_isPositionAccountExist(positionId), PositionAccountNotExists(positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        tradingPrice = _priceOf(_marketOracleId(marketId));
        // allocation (just copy the existing sizes)
        uint256 size;
        uint256[] memory allocations;
        {
            PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
            BackedPoolState[] memory backedPools = _markets[marketId].pools;
            allocations = new uint256[](backedPools.length);
            for (uint256 i = 0; i < backedPools.length; i++) {
                uint256 sizeForPool = positionData.pools[backedPools[i].backedPool].size;
                size += sizeForPool;
                allocations[i] = sizeForPool;
            }
        }
        // update borrowing fee for the current market
        // borrowing fee should be updated before pnl, because profit/loss will affect aum
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(marketId);
        // should mm unsafe
        {
            (uint256 pendingBorrowingFeeUsd, ) = _borrowingFeeUsd(positionId, marketId, cumulatedBorrowingPerUsd);
            require(
                !_isMaintenanceMarginSafe(positionId, pendingBorrowingFeeUsd),
                SafePositionAccount(positionId, SAFE_MAINTENANCE_MARGIN)
            );
        }
        // pnl
        poolPnlUsds = _positionPnlUsd(positionId, marketId, allocations, tradingPrice);
        poolPnlUsds = _realizeProfitAndLoss(
            positionId,
            marketId,
            poolPnlUsds,
            false, // isThrowBankrupt
            lastConsumedToken
        );
        // update borrowing fee
        borrowingFeeUsd = _updateAndDispatchBorrowingFeeForTrade(
            positionAccount.owner,
            positionId,
            marketId,
            cumulatedBorrowingPerUsd,
            false, // shouldCollateralSufficient
            lastConsumedToken
        );
        // position fee
        positionFeeUsd = _dispatchPositionFee(
            positionAccount.owner,
            positionId,
            marketId,
            size,
            allocations,
            true, // isLiquidating
            false, // shouldCollateralSufficient
            lastConsumedToken
        );
        // close position
        _closeMarketPosition(positionId, marketId, allocations);
        _closeAccountPosition(positionId, marketId, allocations);
        // done
        {
            (
                address[] memory backedPools,
                ,
                ,
                address[] memory newCollateralTokens,
                uint256[] memory newCollateralAmounts
            ) = _dumpForTradeEvent(positionId, marketId);
            emit LiquidatePosition(
                positionAccount.owner,
                positionId,
                marketId,
                _markets[marketId].isLong,
                size,
                tradingPrice,
                backedPools,
                allocations,
                poolPnlUsds,
                positionFeeUsd,
                borrowingFeeUsd,
                newCollateralTokens,
                newCollateralAmounts
            );
        }
    }

    // also check FacetPositionAccount.sol: _updateAndDispatchBorrowingFeeForAccount
    // for which is identical
    function _updateAndDispatchBorrowingFeeForTrade(
        address trader,
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory cumulatedBorrowingPerUsd,
        bool shouldCollateralSufficient,
        address lastConsumedToken
    ) private returns (uint256 borrowingFeeUsd) {
        uint256[] memory borrowingFeeUsds;
        address[] memory borrowingFeeAddresses;
        uint256[] memory borrowingFeeAmounts;
        // note: if shouldCollateralSufficient = false, borrowingFeeUsd could <= sum(borrowingFeeUsds).
        //       we only use borrowingFeeUsds as allocations
        (borrowingFeeUsd, borrowingFeeUsds, borrowingFeeAddresses, borrowingFeeAmounts) = _updateAccountBorrowingFee(
            positionId,
            marketId,
            cumulatedBorrowingPerUsd,
            shouldCollateralSufficient,
            lastConsumedToken
        );
        _dispatchFee(
            trader,
            positionId,
            marketId,
            borrowingFeeAddresses,
            borrowingFeeAmounts,
            borrowingFeeUsds // allocations
        );
    }

    function _dispatchPositionFee(
        address trader,
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        uint256[] memory allocations,
        bool isLiquidating,
        bool shouldCollateralSufficient,
        address lastConsumedToken
    ) private returns (uint256 positionFeeUsd) {
        address[] memory positionFeeAddresses;
        uint256[] memory positionFeeAmounts;
        (positionFeeUsd, positionFeeAddresses, positionFeeAmounts) = _updatePositionFee(
            positionId,
            marketId,
            size,
            isLiquidating,
            shouldCollateralSufficient,
            lastConsumedToken
        );
        _dispatchFee(trader, positionId, marketId, positionFeeAddresses, positionFeeAmounts, allocations);
    }

    function _dumpForTradeEvent(
        bytes32 positionId,
        bytes32 marketId
    )
        private
        view
        returns (
            address[] memory backedPools,
            uint256[] memory newSizes,
            uint256[] memory newEntryPrices,
            address[] memory collateralTokens,
            uint256[] memory collateralAmounts
        )
    {
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        // pools
        {
            BackedPoolState[] memory pools = _markets[marketId].pools;
            PositionData storage positionData = positionAccount.positions[marketId];
            backedPools = new address[](pools.length);
            newEntryPrices = new uint256[](pools.length);
            newSizes = new uint256[](pools.length);
            for (uint256 i = 0; i < pools.length; i++) {
                address backedPool = pools[i].backedPool;
                PositionPoolData storage pool = positionData.pools[backedPool];
                backedPools[i] = backedPool;
                newSizes[i] = pool.size;
                newEntryPrices[i] = pool.entryPrice;
            }
        }
        // collaterals
        {
            collateralTokens = positionAccount.activeCollaterals.values();
            collateralAmounts = new uint256[](collateralTokens.length);
            for (uint256 i = 0; i < collateralTokens.length; i++) {
                collateralAmounts[i] = positionAccount.collaterals[collateralTokens[i]];
            }
        }
    }
}
