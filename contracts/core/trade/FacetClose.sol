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
        int256 pnlUsd; // note: poolPnlUsds[] is in LiquidatePositionResult. only used before realize pnl
        uint256[] borrowingFeeUsds; // note: borrowingFeeUsd is in LiquidatePositionResult
        // note: positionFeeUsd is in LiquidatePositionResult
    }

    struct LiquidateMemory {
        LiquidatePositionMemory[] positions;
        uint256 borrowingFeeUsd; // Σ positions[].borrowingFeeUsd. only used before realize pnl
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
     * @notice Liquidate all positions in a PositionAccount.
     * @param args The arguments for liquidating a position
     * @return result The result of liquidating a position
     */
    function liquidate(
        LiquidateArgs memory args
    ) external onlyRole(ORDER_BOOK_ROLE) returns (LiquidateResult memory result) {
        require(_isPositionAccountExist(args.positionId), PositionAccountNotExist(args.positionId));
        // gether information for all markets before liquidating
        LiquidateMemory memory mem;
        _gatherLiquidateInfo(args, mem, result);
        // should mm unsafe
        require(
            !_isMaintenanceMarginSafe(args.positionId, mem.borrowingFeeUsd),
            SafePositionAccount(args.positionId, SAFE_MAINTENANCE_MARGIN)
        );
        // mem.positions[].pnlUsd and mem.borrowingFeeUsd are not used anymore from now on
        // liquidate profit positions first
        for (uint256 i = 0; i < result.positions.length; i++) {
            if (mem.positions[i].pnlUsd >= 0) {
                _liquidatePosition(args, mem, i, result.positions[i]);
            }
        }
        // liquidate loss positions
        for (uint256 i = 0; i < result.positions.length; i++) {
            if (mem.positions[i].pnlUsd < 0) {
                _liquidatePosition(args, mem, i, result.positions[i]);
            }
        }
        // fees and events
        _finalizeLiquidation(args, mem, result);
    }

    function _gatherLiquidateInfo(
        LiquidateArgs memory args,
        LiquidateMemory memory mem,
        LiquidateResult memory result
    ) internal {
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        uint256 markets = positionAccount.activeMarkets.length();
        mem.positions = new LiquidatePositionMemory[](markets);
        result.positions = new LiquidatePositionResult[](markets);
        for (uint256 i = 0; i < markets; i++) {
            // marketId
            bytes32 marketId = positionAccount.activeMarkets.at(i);
            result.positions[i].marketId = marketId;
            // tradingPrice
            result.positions[i].tradingPrice = _priceOf(_marketOracleId(marketId));
            // allocation (just copy the existing sizes)
            (mem.positions[i].size, mem.positions[i].allocations) = _copyPoolSizeAsAllocation(
                args.positionId,
                marketId
            );
            // fees
            // note: borrowing fee should be updated before pnl, because profit/loss will affect aum
            mem.positions[i].cumulatedBorrowingPerUsd = _updateMarketBorrowing(marketId);
            (result.positions[i].borrowingFeeUsd, mem.positions[i].borrowingFeeUsds) = _borrowingFeeUsd(
                args.positionId,
                marketId,
                mem.positions[i].cumulatedBorrowingPerUsd
            );
            mem.borrowingFeeUsd += result.positions[i].borrowingFeeUsd;
            result.positions[i].positionFeeUsd = _positionFeeUsd(marketId, mem.positions[i].size, true);
            // pnl
            result.positions[i].poolPnlUsds = _positionPnlUsd(
                args.positionId,
                marketId,
                mem.positions[i].allocations,
                result.positions[i].tradingPrice,
                true /* useCappedPnl */
            );
            for (uint256 j = 0; j < result.positions[i].poolPnlUsds.length; j++) {
                mem.positions[i].pnlUsd += result.positions[i].poolPnlUsds[j];
            }
        }
    }

    function _liquidatePosition(
        LiquidateArgs memory args,
        LiquidateMemory memory mem,
        uint256 i, // position index in mem.positions and result.positions
        LiquidatePositionResult memory result
    ) internal {
        if (_marketDisableTrade(result.marketId)) {
            // theoretically, we should liquidate all positions. but we really do not want to block the liquidate process
            return;
        }
        // pnl
        result.poolPnlUsds = _realizeProfitAndLoss(
            args.positionId,
            result.marketId,
            result.poolPnlUsds,
            false, // isThrowBankrupt
            args.lastConsumedToken
        );
        // close position
        _closeMarketPosition(args.positionId, result.marketId, mem.positions[i].allocations);
        _closeAccountPosition(args.positionId, result.marketId, mem.positions[i].allocations);
    }

    function _finalizeLiquidation(
        LiquidateArgs memory args,
        LiquidateMemory memory mem,
        LiquidateResult memory result
    ) internal {
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        // fees are optional
        for (uint256 i = 0; i < result.positions.length; i++) {
            bytes32 marketId = result.positions[i].marketId;
            if (_marketDisableTrade(marketId)) {
                // skipped in previous steps
                continue;
            }
            // update borrowing fee, similar to _updateAndDispatchBorrowingFee
            // but the position is already closed
            {
                address[] memory borrowingFeeAddresses;
                uint256[] memory borrowingFeeAmounts;
                (
                    result.positions[i].borrowingFeeUsd,
                    borrowingFeeAddresses,
                    borrowingFeeAmounts
                ) = _collectFeeFromCollateral(
                    args.positionId,
                    result.positions[i].borrowingFeeUsd,
                    false, // shouldCollateralSufficient
                    args.lastConsumedToken
                );
                _dispatchFee(
                    positionAccount.owner,
                    marketId,
                    borrowingFeeAddresses,
                    borrowingFeeAmounts,
                    mem.positions[i].allocations, // allocations
                    args.isUnwrapWeth
                );
            }
            // position fee, similar to _dispatchPositionFee
            // but the position is already closed
            {
                address[] memory positionFeeAddresses;
                uint256[] memory positionFeeAmounts;
                (
                    result.positions[i].positionFeeUsd,
                    positionFeeAddresses,
                    positionFeeAmounts
                ) = _collectFeeFromCollateral(
                    args.positionId,
                    result.positions[i].positionFeeUsd,
                    false, // shouldCollateralSufficient
                    args.lastConsumedToken
                );
                _dispatchFee(
                    positionAccount.owner,
                    marketId,
                    positionFeeAddresses,
                    positionFeeAmounts,
                    mem.positions[i].allocations,
                    args.isUnwrapWeth
                );
            }
            // event
            {
                (
                    address[] memory backedPools,
                    ,
                    ,
                    address[] memory newCollateralTokens,
                    uint256[] memory newCollateralAmounts
                ) = _dumpForTradeEvent(args.positionId, marketId);
                emit LiquidatePosition(
                    positionAccount.owner,
                    args.positionId,
                    marketId,
                    _markets[marketId].isLong,
                    mem.positions[i].size, // old size = liquidate size
                    result.positions[i].tradingPrice,
                    backedPools,
                    mem.positions[i].allocations,
                    result.positions[i].poolPnlUsds,
                    result.positions[i].positionFeeUsd,
                    result.positions[i].borrowingFeeUsd,
                    newCollateralTokens,
                    newCollateralAmounts
                );
            }
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
