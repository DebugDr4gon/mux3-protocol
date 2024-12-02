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

    struct LiquidatePositionMemory {
        uint256 size;
        uint256[] allocations;
        uint256[] cumulatedBorrowingPerUsd;
    }

    /**
     * @notice The entry point for closing a position
     * @param args The arguments for closing a position
     * @return result The result of closing a position
     */
    function closePosition(
        ClosePositionArgs memory args
    ) external onlyRole(ORDER_BOOK_ROLE) returns (ClosePositionResult memory result) {
        {
            uint256 lotSize = _marketLotSize(args.marketId);
            require(args.size % lotSize == 0, InvalidLotSize(args.size, lotSize));
        }
        require(_isMarketExist(args.marketId), MarketNotExists(args.marketId));
        require(!_marketDisableTrade(args.marketId), MarketTradeDisabled(args.marketId));
        require(_isPositionAccountExist(args.positionId), PositionAccountNotExist(args.positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        result.tradingPrice = _priceOf(_marketOracleId(args.marketId));
        // allocation
        uint256[] memory allocations = _deallocateLiquidity(args.positionId, args.marketId, args.size);
        // update borrowing fee for the current market
        // note: we do not update borrowing fees for other markets to keep the contract simple.
        //       mux3-broker would periodically update borrowing fees for unclosed positions.
        // note: borrowing fee should be updated before pnl, because profit/loss will affect aum
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(args.marketId);
        // pnl
        result.poolPnlUsds = _positionPnlUsd(
            args.positionId,
            args.marketId,
            allocations,
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
            cumulatedBorrowingPerUsd,
            false, // shouldCollateralSufficient
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
            false, // shouldCollateralSufficient
            args.lastConsumedToken,
            args.isUnwrapWeth
        );
        // close position
        _closeMarketPosition(args.positionId, args.marketId, allocations);
        _closeAccountPosition(args.positionId, args.marketId, allocations);
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
            emit ClosePosition(
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
                result.poolPnlUsds,
                result.positionFeeUsd,
                result.borrowingFeeUsd,
                newCollateralTokens,
                newCollateralAmounts
            );
        }
    }

    /**
     * @notice Liquidate a position (of all pool allocations) in a position account. Leave other positions in this position account.
     * @param args The arguments for liquidating a position
     * @return result The result of liquidating a position
     */
    function liquidatePosition(
        LiquidatePositionArgs memory args
    ) external onlyRole(ORDER_BOOK_ROLE) returns (LiquidatePositionResult memory result) {
        LiquidatePositionMemory memory mem;
        require(_isMarketExist(args.marketId), MarketNotExists(args.marketId));
        require(!_marketDisableTrade(args.marketId), MarketTradeDisabled(args.marketId));
        require(_isPositionAccountExist(args.positionId), PositionAccountNotExist(args.positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        result.tradingPrice = _priceOf(_marketOracleId(args.marketId));
        // allocation (just copy the existing sizes)
        (mem.size, mem.allocations) = _copyPoolSizeAsAllocation(args.positionId, args.marketId);
        // update borrowing fee for the current market
        // note: we do not update borrowing fees for other markets to keep the contract simple.
        //       mux3-broker would periodically update borrowing fees for unclosed positions.
        // note: borrowing fee should be updated before pnl, because profit/loss will affect aum
        mem.cumulatedBorrowingPerUsd = _updateMarketBorrowing(args.marketId);
        // should mm unsafe
        {
            (uint256 pendingBorrowingFeeUsd, ) = _borrowingFeeUsd(
                args.positionId,
                args.marketId,
                mem.cumulatedBorrowingPerUsd
            );
            require(
                !_isMaintenanceMarginSafe(args.positionId, pendingBorrowingFeeUsd),
                SafePositionAccount(args.positionId, SAFE_MAINTENANCE_MARGIN)
            );
        }
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
            false, // isThrowBankrupt
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
        // position fee
        result.positionFeeUsd = _dispatchPositionFee(
            positionAccount.owner,
            args.positionId,
            args.marketId,
            mem.size,
            mem.allocations,
            true, // isLiquidating
            false, // shouldCollateralSufficient
            args.lastConsumedToken,
            args.isUnwrapWeth
        );
        // close position
        _closeMarketPosition(args.positionId, args.marketId, mem.allocations);
        _closeAccountPosition(args.positionId, args.marketId, mem.allocations);
        // done
        {
            (
                address[] memory backedPools,
                ,
                ,
                address[] memory newCollateralTokens,
                uint256[] memory newCollateralAmounts
            ) = _dumpForTradeEvent(args.positionId, args.marketId);
            emit LiquidatePosition(
                positionAccount.owner,
                args.positionId,
                args.marketId,
                _markets[args.marketId].isLong,
                mem.size,
                result.tradingPrice,
                backedPools,
                mem.allocations,
                result.poolPnlUsds,
                result.positionFeeUsd,
                result.borrowingFeeUsd,
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
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        allocations = new uint256[](backedPools.length);
        for (uint256 i = 0; i < backedPools.length; i++) {
            uint256 sizeForPool = positionData.pools[backedPools[i].backedPool].size;
            size += sizeForPool;
            allocations[i] = sizeForPool;
        }
    }
}
