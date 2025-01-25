// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../../interfaces/IFacetTrade.sol";
import "../../libraries/LibTypeCast.sol";
import "./TradeBase.sol";

contract FacetOpen is Mux3TradeBase, IFacetOpen {
    using LibTypeCast for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using LibConfigMap for mapping(bytes32 => bytes32);

    struct ReallocatePositionMemory {
        uint256 fromIndex;
        uint256 toIndex;
        uint256 fromPoolOldEntryPrice; // previous entry price from the fromPool
        uint256[] allocations;
        uint256[] cumulatedBorrowingPerUsd;
        int256[] poolPnlUsds;
    }

    /**
     * @notice The entry point for opening a position
     * @param args The arguments for opening a position
     * @return result The result of opening a position
     */
    function openPosition(
        OpenPositionArgs memory args
    ) external onlyRole(ORDER_BOOK_ROLE) returns (OpenPositionResult memory result) {
        {
            uint256 lotSize = _marketLotSize(args.marketId);
            require(args.size % lotSize == 0, InvalidLotSize(args.size, lotSize));
        }
        require(_isMarketExist(args.marketId), MarketNotExists(args.marketId));
        require(!_marketDisableTrade(args.marketId), MarketTradeDisabled(args.marketId));
        require(!_marketDisableOpen(args.marketId), MarketTradeDisabled(args.marketId));
        if (!_isPositionAccountExist(args.positionId)) {
            _createPositionAccount(args.positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        result.tradingPrice = _priceOf(_marketOracleId(args.marketId));
        uint256[] memory allocations = _allocateLiquidity(args.marketId, args.size);
        // update borrowing fee for the current market
        // note: we do not update borrowing fees for other markets to keep the contract simple.
        //       mux3-broker would periodically update borrowing fees for unclosed positions.
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(args.marketId);
        result.borrowingFeeUsd = _updateAndDispatchBorrowingFee(
            positionAccount.owner,
            args.positionId,
            args.marketId,
            cumulatedBorrowingPerUsd,
            true, // shouldCollateralSufficient
            args.lastConsumedToken,
            args.isUnwrapWeth
        );
        // position fee
        result.positionFeeUsd = _dispatchPositionFee(
            positionAccount.owner,
            args.positionId,
            args.marketId,
            args.size,
            allocations,
            false, // isLiquidating
            true, // shouldCollateralSufficient
            args.lastConsumedToken,
            args.isUnwrapWeth
        );
        // open position
        _openMarketPosition(args.marketId, allocations, result.tradingPrice);
        _openAccountPosition(
            args.positionId,
            args.marketId,
            allocations,
            cumulatedBorrowingPerUsd,
            result.tradingPrice
        );
        // exceeds leverage set by setInitialLeverage
        require(_isLeverageSafe(args.positionId), UnsafePositionAccount(args.positionId, SAFE_LEVERAGE));
        // exceeds leverage set by MM_INITIAL_MARGIN_RATE
        require(_isInitialMarginSafe(args.positionId), UnsafePositionAccount(args.positionId, SAFE_INITIAL_MARGIN));
        // done
        {
            (
                address[] memory backedPools,
                uint256[] memory newSizes,
                uint256[] memory newEntryPrices,
                address[] memory newCollateralTokens,
                uint256[] memory newCollateralAmounts
            ) = _dumpForTradeEvent(args.positionId, args.marketId);
            emit OpenPosition(
                positionAccount.owner,
                args.positionId,
                args.marketId,
                _markets[args.marketId].isLong,
                args.size,
                result.tradingPrice,
                backedPools,
                allocations,
                newSizes,
                newEntryPrices,
                result.positionFeeUsd,
                result.borrowingFeeUsd,
                newCollateralTokens,
                newCollateralAmounts
            );
        }
    }

    /**
     * @notice Reallocate a position from one pool to another. The Broker uses this function to maintain a consistent
     *         borrowing fee rate after position closing and liquidity changes by:
     *         1. Transfer position from fromPool to toPool
     *         2. Keep the trader's overall average entry price unchanged (while individual pool entry prices may change)
     *         3. Settle unrealized PnL between the two pools without affecting pool NAV
     *
     * @dev This function only verifies that the account remains safe after reallocation, without validating
     *      the economic rationale of the reallocation strategy.
     * @dev Borrowing fees will be deducted from collateral. Position fees are not charged since this is not
     *      initiated by trader's intention. However, the external contract can implement its own fee strategy.
     * @dev Reallocation strategy suggestions:
     *      1. If the PnL of fromPool is capped, toPool will incur a loss. This can be prevented by either
     *         using ADL on this position or by reallocating other positions.
     *      2. If PnL is negative, toPool will compensate fromPool with collateral. This could lead to insufficient reserves in toPool
     *         (i.e., poolCollateralUsd < reservedUsd), which needs to be prevented.
     */
    function reallocatePosition(
        ReallocatePositionArgs memory args
    ) external onlyRole(ORDER_BOOK_ROLE) returns (ReallocatePositionResult memory result) {
        ReallocatePositionMemory memory mem;
        {
            uint256 lotSize = _marketLotSize(args.marketId);
            require(args.size % lotSize == 0, InvalidLotSize(args.size, lotSize));
        }
        require(_isMarketExist(args.marketId), MarketNotExists(args.marketId));
        require(!_marketDisableTrade(args.marketId), MarketTradeDisabled(args.marketId));
        require(_isPositionAccountExist(args.positionId), PositionAccountNotExist(args.positionId));
        mem.fromIndex = _findBackedPoolIndex(args.marketId, args.fromPool);
        mem.toIndex = _findBackedPoolIndex(args.marketId, args.toPool);
        result.tradingPrice = _priceOf(_marketOracleId(args.marketId));
        {
            // allocate all to fromPool
            uint256 backedPoolLength = _markets[args.marketId].pools.length;
            mem.allocations = new uint256[](backedPoolLength);
            mem.allocations[mem.fromIndex] = args.size;
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        {
            PositionData storage positionData = positionAccount.positions[args.marketId];
            require(
                args.size <= positionData.pools[args.fromPool].size,
                InvalidCloseSize(args.size, positionData.pools[args.fromPool].size)
            );
            // unlike openPosition which calculates new entryPrice according to marketPrice,
            // reallocate does not change the overall average entry price, thus it
            // calculates position.pools[toPool].entryPrice based on position.pools[fromPool].entryPrice
            mem.fromPoolOldEntryPrice = positionData.pools[args.fromPool].entryPrice;
        }
        // update borrowing fee for the current market
        // note: we do not update borrowing fees for other markets to keep the contract simple.
        //       mux3-broker would periodically update borrowing fees for unclosed positions.
        mem.cumulatedBorrowingPerUsd = _updateMarketBorrowing(args.marketId);
        // pnl
        // note: if the pnl is capped, toPool will suffer from a loss, because fromPool only
        //       sends cappedPnl to toPnl while the entryPrice is the original one.
        mem.poolPnlUsds = _positionPnlUsd(
            args.positionId,
            args.marketId,
            mem.allocations,
            result.tradingPrice,
            true /* useCappedPnl */
        );
        // update borrowing fee
        result.borrowingFeeUsd = _updateAndDispatchBorrowingFee(
            positionAccount.owner,
            args.positionId,
            args.marketId,
            mem.cumulatedBorrowingPerUsd,
            false, // shouldCollateralSufficient
            args.lastConsumedToken,
            args.isUnwrapWeth
        );
        // transfer trader's position. open then close, so that PositionAccount won't recognize this as fully closed
        mem.allocations[mem.fromIndex] = 0;
        mem.allocations[mem.toIndex] = args.size;
        _openAccountPosition(
            args.positionId,
            args.marketId,
            mem.allocations,
            mem.cumulatedBorrowingPerUsd,
            mem.fromPoolOldEntryPrice
        );
        mem.allocations[mem.fromIndex] = args.size;
        mem.allocations[mem.toIndex] = 0;
        _closeAccountPosition(args.positionId, args.marketId, mem.allocations);
        // transfer pool's position and settle PnL between them
        mem.poolPnlUsds[mem.fromIndex] = _reallocateMarketPosition(
            args.marketId,
            args.fromPool,
            args.toPool,
            args.size,
            mem.fromPoolOldEntryPrice,
            mem.poolPnlUsds[mem.fromIndex]
        );
        // should safe
        require(
            _isMaintenanceMarginSafe(
                args.positionId,
                0 // pendingBorrowingFeeUsd = 0 because we have already deducted borrowing fee from collaterals
            ),
            UnsafePositionAccount(args.positionId, SAFE_MAINTENANCE_MARGIN)
        );
        // prevent insufficient reserves in pools. we do not need to check fromPool as it should have enough reserves to pay the pnl.
        // however, we need to verify toPool has sufficient reserves
        {
            uint256 poolCollateralUsd = ICollateralPool(args.toPool).getCollateralTokenUsd();
            uint256 reservedUsd = ICollateralPool(args.toPool).getReservedUsd();
            require(reservedUsd <= poolCollateralUsd, InsufficientLiquidity(reservedUsd, poolCollateralUsd));
        }
        // done
        {
            (
                address[] memory backedPools,
                uint256[] memory newSizes,
                uint256[] memory newEntryPrices,
                address[] memory newCollateralTokens,
                uint256[] memory newCollateralAmounts
            ) = _dumpForTradeEvent(args.positionId, args.marketId);
            emit ReallocatePosition(
                positionAccount.owner,
                args.positionId,
                args.marketId,
                _markets[args.marketId].isLong,
                args.fromPool,
                args.toPool,
                args.size,
                result.tradingPrice,
                mem.fromPoolOldEntryPrice,
                backedPools,
                newSizes,
                newEntryPrices,
                mem.poolPnlUsds,
                result.borrowingFeeUsd,
                newCollateralTokens,
                newCollateralAmounts
            );
        }
    }

    function _findBackedPoolIndex(bytes32 marketId, address poolAddress) private view returns (uint256 index) {
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        for (uint256 i = 0; i < backedPools.length; i++) {
            if (backedPools[i].backedPool == poolAddress) {
                return i;
            }
        }
        revert PoolNotExists(poolAddress);
    }
}
