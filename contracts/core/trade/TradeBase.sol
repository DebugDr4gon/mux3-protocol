// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../Mux3FacetBase.sol";
import "./PositionAccount.sol";
import "./Market.sol";

contract Mux3TradeBase is Mux3FacetBase, PositionAccount, Market {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function _updateAndDispatchBorrowingFee(
        address trader,
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory cumulatedBorrowingPerUsd,
        bool shouldCollateralSufficient,
        address lastConsumedToken
    ) internal returns (uint256 borrowingFeeUsd) {
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
    ) internal returns (uint256 positionFeeUsd) {
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
        internal
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
