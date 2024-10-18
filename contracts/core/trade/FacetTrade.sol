// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../../interfaces/ITrade.sol";
import "../../libraries/LibTypeCast.sol";

import "../Mux3FacetBase.sol";
import "./PositionAccount.sol";
import "./Market.sol";
import "./Pricing.sol";

contract FacetTrade is Mux3FacetBase, PositionAccount, Market, Pricing, ITrade {
    using LibTypeCast for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    /**
     * @dev updates the borrowing fee for a position, allowing LPs to collect fees
     *      even if the position remains open.
     */
    function updateBorrowingFee(bytes32 marketId, bytes32 positionId) external {
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // update borrowing fee
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(
            marketId
        );
        uint256 borrowingFeeUsd = _updateAndDispatchBorrowingFee(
            positionAccount.owner,
            marketId,
            positionId,
            cumulatedBorrowingPerUsd,
            true
        );
        emit UpdatePositionBorrowingFee(
            positionAccount.owner,
            positionId,
            marketId,
            borrowingFeeUsd
        );
    }

    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 leverage
    ) external {
        // auth
        // _checkAuthorization(positionId); // TODO: broker only?
        // make account if nessary
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // set leverage
        _setInitialLeverage(positionId, marketId, leverage);
        emit SetInitialLeverage(
            positionAccount.owner,
            positionId,
            marketId,
            leverage
        );
    }

    function deposit(
        bytes32 positionId,
        address collateralToken,
        uint256 rawAmount // token.decimals
    ) external {
        // auth
        // _checkAuthorization(positionId); // TODO: broker only?
        // make account if nessary
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // deposit
        _depositToAccount(positionId, collateralToken, rawAmount);
        emit Deposit(
            positionAccount.owner,
            positionId,
            collateralToken,
            rawAmount
        );
    }

    function withdraw(
        bytes32 positionId,
        address collateralToken,
        uint256 rawAmount // token.decimals
    ) external {
        // TODO: broker only
        // auth
        // _checkAuthorization(positionId); // TODO: broker only?
        require(
            _isPositionAccountExist(positionId),
            PositionAccountNotExists(positionId)
        );
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // update all borrowing fee
        uint256 allBorrowingFeeUsd;
        uint256 marketLength = positionAccount.activeMarkets.length();
        for (uint256 i = 0; i < marketLength; i++) {
            bytes32 marketId = positionAccount.activeMarkets.at(i);
            uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(
                marketId
            );
            uint256 borrowingFeeUsd = _updateAndDispatchBorrowingFee(
                positionAccount.owner,
                marketId,
                positionId,
                cumulatedBorrowingPerUsd,
                true
            );
            allBorrowingFeeUsd += borrowingFeeUsd;
        }
        // withdraw
        uint256 collateralAmount = _collateralToWad(collateralToken, rawAmount);
        _withdrawFromAccount(positionId, collateralToken, collateralAmount);
        emit Withdraw(
            positionAccount.owner,
            positionId,
            collateralToken,
            rawAmount,
            allBorrowingFeeUsd
        );
    }

    function withdrawAll(bytes32 positionId) external {
        // TODO: broker only
        // auth
        // _checkAuthorization(positionId); // TODO: broker only?
        require(
            _isPositionAccountExist(positionId),
            PositionAccountNotExists(positionId)
        );
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // all positions should be closed
        require(
            positionAccount.activeMarkets.length() == 0,
            PositionNotClosed(positionId)
        );
        address[] memory collaterals = positionAccount
            .activeCollaterals
            .values();
        for (uint256 i = 0; i < collaterals.length; i++) {
            address collateralToken = collaterals[i];
            uint256 collateralAmount = positionAccount.collaterals[
                collaterals[i]
            ];
            _withdrawFromAccount(positionId, collateralToken, collateralAmount);
            emit Withdraw(
                positionAccount.owner,
                positionId,
                collateralToken,
                _collateralToRaw(collateralToken, collateralAmount),
                0 // borrowingFee must be 0 because size is 0
            );
        }
    }

    function openPosition(
        bytes32 marketId,
        bytes32 positionId,
        uint256 size
    ) external onlyRole(ORDER_BOOK_ROLE) returns (uint256 tradingPrice) {
        require(
            size % _marketLotSize(marketId) == 0,
            InvalidPositionSize(size)
        );
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        // TODO: ASSET_IS_TRADABLE
        // TODO: ASSET_IS_OPENABLE
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        tradingPrice = _priceOf(marketId);
        uint256[] memory allocations = _allocateLiquidity(marketId, size);
        // update borrowing fee
        uint256 borrowingFeeUsd;
        {
            uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(
                marketId
            );
            borrowingFeeUsd = _updateAndDispatchBorrowingFee(
                positionAccount.owner,
                marketId,
                positionId,
                cumulatedBorrowingPerUsd,
                true
            );
        }
        // position fee
        uint256 positionFeeUsd = _dispatchPositionFee(
            positionAccount.owner,
            marketId,
            positionId,
            size,
            allocations,
            true
        );
        // open position
        _openMarketPosition(marketId, allocations);
        _openAccountPosition(positionId, marketId, allocations);
        // done
        {
            (
                address[] memory backedPools,
                uint256[] memory newSizes,
                uint256[] memory newEntryPrices,
                address[] memory newCollateralTokens,
                uint256[] memory newCollateralAmounts
            ) = _dumpForEvent(marketId, positionId);
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
        bytes32 marketId,
        bytes32 positionId,
        uint256 size
    ) external onlyRole(ORDER_BOOK_ROLE) returns (uint256 tradingPrice) {
        require(
            size % _marketLotSize(marketId) == 0,
            InvalidPositionSize(size)
        );
        require(_isMarketExists(marketId), MarketNotExists(marketId));
        // TODO: ASSET_IS_TRADABLE
        require(
            _isPositionAccountExist(positionId),
            PositionAccountNotExists(positionId)
        );
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        tradingPrice = _priceOf(marketId);
        uint256[] memory allocations = _deallocateLiquidity(
            positionId,
            marketId,
            size
        );
        // borrowing fee should be updated before pnl, because profit/loss will affect aum
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(
            marketId
        );
        // pnl
        (
            bool[] memory hasProfits,
            uint256[] memory poolPnlUsds
        ) = _positionPnlUsd(marketId, positionId, allocations, tradingPrice);
        poolPnlUsds = _realizeProfitAndLoss(
            marketId,
            positionId,
            hasProfits,
            poolPnlUsds,
            true
        );
        // update borrowing fee
        uint256 borrowingFeeUsd = _updateAndDispatchBorrowingFee(
            positionAccount.owner,
            marketId,
            positionId,
            cumulatedBorrowingPerUsd,
            false
        );
        // position fee
        uint256 positionFeeUsd = _dispatchPositionFee(
            positionAccount.owner,
            marketId,
            positionId,
            size,
            allocations,
            false
        );
        // close position
        _closeMarketPosition(positionId, marketId, allocations);
        _closeAccountPosition(positionId, marketId, allocations);
        // done
        {
            (
                address[] memory backedPools,
                uint256[] memory newSizes,
                uint256[] memory newEntryPrices,
                address[] memory newCollateralTokens,
                uint256[] memory newCollateralAmounts
            ) = _dumpForEvent(marketId, positionId);
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
                hasProfits,
                poolPnlUsds,
                positionFeeUsd,
                borrowingFeeUsd,
                newCollateralTokens,
                newCollateralAmounts
            );
        }
    }

    function setPrice(
        bytes32 priceId,
        address provider,
        bytes memory oracleCalldata
    ) external onlyRole(BROKER_ROLE) {
        (uint256 price, uint256 timestamp) = _setPrice(
            priceId,
            provider,
            oracleCalldata
        );
        emit SetPrice(priceId, provider, oracleCalldata, price, timestamp);
    }

    function _updateAndDispatchBorrowingFee(
        address trader,
        bytes32 marketId,
        bytes32 positionId,
        uint256[] memory cumulatedBorrowingPerUsd,
        bool shouldCollateralSufficient
    ) private returns (uint256 borrowingFeeUsd) {
        uint256[] memory borrowingFeeUsds;
        address[] memory borrowingFeeAddresses;
        uint256[] memory borrowingFeeAmounts;
        // note: if shouldCollateralSufficient = false, borrowingFeeUsd could <= sum(borrowingFeeUsds).
        //       we only use borrowingFeeUsds as allocations
        (
            borrowingFeeUsd,
            borrowingFeeUsds,
            borrowingFeeAddresses,
            borrowingFeeAmounts
        ) = _updateAccountBorrowingFee(
            marketId,
            positionId,
            cumulatedBorrowingPerUsd,
            shouldCollateralSufficient
        );
        _dispatchFee(
            trader,
            marketId,
            positionId,
            borrowingFeeAddresses,
            borrowingFeeAmounts,
            borrowingFeeUsds // allocations
        );
    }

    function _dispatchPositionFee(
        address trader,
        bytes32 marketId,
        bytes32 positionId,
        uint256 size,
        uint256[] memory allocations,
        bool shouldCollateralSufficient
    ) private returns (uint256 positionFeeUsd) {
        address[] memory positionFeeAddresses;
        uint256[] memory positionFeeAmounts;
        (
            positionFeeUsd,
            positionFeeAddresses,
            positionFeeAmounts
        ) = _updatePositionFee(
            positionId,
            marketId,
            size,
            shouldCollateralSufficient
        );
        _dispatchFee(
            trader,
            marketId,
            positionId,
            positionFeeAddresses,
            positionFeeAmounts,
            allocations
        );
    }

    function _dumpForEvent(
        bytes32 marketId,
        bytes32 positionId
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
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // pools
        {
            BackedPoolState[] memory pools = _markets[marketId].pools;
            PositionData storage positionData = positionAccount.positions[
                marketId
            ];
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
                collateralAmounts[i] = positionAccount.collaterals[
                    collateralTokens[i]
                ];
            }
        }
    }
}
