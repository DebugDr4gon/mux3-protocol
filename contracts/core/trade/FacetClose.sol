// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../../interfaces/IFacetTrade.sol";
import "../../libraries/LibTypeCast.sol";
import "./TradeBase.sol";

contract FacetClose is Mux3TradeBase, IFacetClose {
    using LibTypeCast for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using LibConfigMap for mapping(bytes32 => bytes32);

    /**
     * @notice The entry point for closing a position
     */
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
        {
            uint256 lotSize = _marketLotSize(marketId);
            require(size % lotSize == 0, InvalidLotSize(size, lotSize));
        }
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        require(!_marketDisableTrade(marketId), MarketTradeDisabled(marketId));
        require(_isPositionAccountExist(positionId), PositionAccountNotExists(positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        tradingPrice = _priceOf(_marketOracleId(marketId));
        // allocation
        uint256[] memory allocations = _deallocateLiquidity(positionId, marketId, size);
        // update borrowing fee for the current market
        // borrowing fee should be updated before pnl, because profit/loss will affect aum
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(marketId);
        // pnl
        poolPnlUsds = _positionPnlUsd(positionId, marketId, allocations, tradingPrice, true /* useCappedPnl */);
        poolPnlUsds = _realizeProfitAndLoss(
            positionId,
            marketId,
            poolPnlUsds,
            true, // isThrowBankrupt
            lastConsumedToken
        );
        // update borrowing fee
        borrowingFeeUsd = _updateAndDispatchBorrowingFee(
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

    /**
     * @notice Liquidate a position (of all pool allocations) in a position account. Leave other positions in this position account.
     */
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
        require(!_marketDisableTrade(marketId), MarketTradeDisabled(marketId));
        require(_isPositionAccountExist(positionId), PositionAccountNotExists(positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        tradingPrice = _priceOf(_marketOracleId(marketId));
        // allocation (just copy the existing sizes)
        (uint256 size, uint256[] memory allocations) = _copyPoolSizeAsAllocation(positionId, marketId);
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
        poolPnlUsds = _positionPnlUsd(positionId, marketId, allocations, tradingPrice, true /* useCappedPnl */);
        poolPnlUsds = _realizeProfitAndLoss(
            positionId,
            marketId,
            poolPnlUsds,
            false, // isThrowBankrupt
            lastConsumedToken
        );
        // update borrowing fee
        borrowingFeeUsd = _updateAndDispatchBorrowingFee(
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

    function _copyPoolSizeAsAllocation(
        bytes32 positionId,
        bytes32 marketId
    ) private view returns (uint256 size, uint256[] memory allocations) {
        PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        allocations = new uint256[](backedPools.length);
        for (uint256 i = 0; i < backedPools.length; i++) {
            uint256 sizeForPool = positionData.pools[backedPools[i].backedPool].size;
            size += sizeForPool;
            allocations[i] = sizeForPool;
        }
    }
}
