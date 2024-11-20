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

    /**
     * @notice The entry point for opening a position
     */
    function openPosition(
        OpenPositionArgs memory args
    ) external onlyRole(ORDER_BOOK_ROLE) returns (OpenPositionResult memory result) {
        {
            uint256 lotSize = _marketLotSize(args.marketId);
            require(args.size % lotSize == 0, InvalidLotSize(args.size, lotSize));
        }
        require(_isMarketExists(args.marketId), MarketNotExists(args.marketId));
        require(!_marketDisableTrade(args.marketId), MarketTradeDisabled(args.marketId));
        require(!_marketDisableOpen(args.marketId), MarketTradeDisabled(args.marketId));
        if (!_isPositionAccountExist(args.positionId)) {
            _createPositionAccount(args.positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        result.tradingPrice = _priceOf(_marketOracleId(args.marketId));
        uint256[] memory allocations = _allocateLiquidity(args.marketId, args.size);
        // update borrowing fee for the current market
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
        _openMarketPosition(args.marketId, allocations);
        _openAccountPosition(args.positionId, args.marketId, allocations, cumulatedBorrowingPerUsd);
        // exceeds leverage set by setInitialLeverage
        require(_isLeverageSafe(args.positionId), UnsafePositionAccount(args.positionId, SAFE_LEVERAGE));
        // exceeds leverage set by MM_INITIAL_MARGIN_RATE
        require(_isInitialMarginSafe(args.positionId), UnsafePositionAccount(args.positionId, SAFE_INITITAL_MARGIN));
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

    struct ReallocatePositionMemory {
        uint256 fromIndex;
        uint256 toIndex;
        uint256[] allocations;
        uint256[] cumulatedBorrowingPerUsd;
    }

    /**
     * @notice Reallocate a position from one pool to another. The Broker will use this function to move positions to
     *         high-priority pools after positions in high-priority pools are closed/liquidated. This helps ensure
     *         high-priority pools can maintain as many positions as possible.
     *
     *         This function closes the position in fromPool and opens a new position in toPool. This function only
     *         ensures the account remains safe, without verifying if the reallocation strategy makes sense.
     *
     *         This function charges borrowingFees from collateral, but does not charge positionFees (because closing
     *         position is not Trader's intention).
     */
    function reallocatePosition(
        ReallocatePositionArgs memory args
    ) external onlyRole(ORDER_BOOK_ROLE) returns (ReallocatePositionResult memory result) {
        ReallocatePositionMemory memory mem;
        {
            uint256 lotSize = _marketLotSize(args.marketId);
            require(args.size % lotSize == 0, InvalidLotSize(args.size, lotSize));
        }
        require(_isMarketExists(args.marketId), MarketNotExists(args.marketId));
        require(!_marketDisableTrade(args.marketId), MarketTradeDisabled(args.marketId));
        require(_isPositionAccountExist(args.positionId), PositionAccountNotExists(args.positionId));
        mem.fromIndex = _findBackedPoolIndex(args.marketId, args.fromPool);
        mem.toIndex = _findBackedPoolIndex(args.marketId, args.toPool);
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        result.tradingPrice = _priceOf(_marketOracleId(args.marketId));
        {
            uint256 backedPoolLength = _markets[args.marketId].pools.length;
            mem.allocations = new uint256[](backedPoolLength);
            mem.cumulatedBorrowingPerUsd = new uint256[](backedPoolLength);
        }
        // allocation all to fromPool
        mem.allocations[mem.fromIndex] = args.size;
        {
            PositionData storage positionData = positionAccount.positions[args.marketId];
            require(
                positionData.pools[args.fromPool].size >= args.size,
                AllocationPositionMismatch(positionData.pools[args.fromPool].size, args.size)
            );
        }
        // update borrowing fee only for fromIndex and toIndex
        mem.cumulatedBorrowingPerUsd[mem.fromIndex] = ICollateralPool(args.fromPool).updateMarketBorrowing(
            args.marketId
        );
        mem.cumulatedBorrowingPerUsd[mem.toIndex] = ICollateralPool(args.toPool).updateMarketBorrowing(args.marketId);
        // pnl
        result.poolPnlUsds = _positionPnlUsd(
            args.positionId,
            args.marketId,
            mem.allocations,
            result.tradingPrice,
            true /* useCappedPnl */
        );
        result.poolPnlUsds = _realizeProfitAndLoss(
            args.positionId,
            args.marketId,
            result.poolPnlUsds,
            true, // isThrowBankrupt
            args.lastConsumedToken
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
        // close position
        _closeMarketPosition(args.positionId, args.marketId, mem.allocations);
        _closeAccountPosition(args.positionId, args.marketId, mem.allocations);
        // open position
        mem.allocations[mem.fromIndex] = 0;
        mem.allocations[mem.toIndex] = args.size;
        _openMarketPosition(args.marketId, mem.allocations);
        _openAccountPosition(args.positionId, args.marketId, mem.allocations, mem.cumulatedBorrowingPerUsd);
        // should safe
        require(
            _isMaintenanceMarginSafe(
                args.positionId,
                0 // pendingBorrowingFeeUsd = 0 because we have already deducted borrowing fee from collaterals
            ),
            UnsafePositionAccount(args.positionId, SAFE_MAINTENANCE_MARGIN)
        );
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
                backedPools,
                newSizes,
                newEntryPrices,
                result.poolPnlUsds,
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
