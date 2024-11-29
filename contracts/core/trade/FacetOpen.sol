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
}
