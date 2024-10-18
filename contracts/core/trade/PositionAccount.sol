// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../../libraries/LibCodec.sol";
import "../../interfaces/IPositionAccount.sol";

import "../Mux3FacetBase.sol";

import "hardhat/console.sol";

contract PositionAccount is Mux3FacetBase {
    using LibCodec for bytes32;
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 initialLeverage
    ) internal {
        require(
            initialLeverage >= 1e18,
            InitialLeverageOutOfRange(initialLeverage, 1e18)
        );
        uint256 maxLeverage = _marketMaxInitialLeverage(marketId);
        require(
            initialLeverage <= maxLeverage,
            InitialLeverageOutOfRange(initialLeverage, maxLeverage)
        );
        _positionAccounts[positionId]
            .positions[marketId]
            .initialLeverage = initialLeverage;
    }

    // OrderBook should transfer collateralToken to this contract
    function _depositToAccount(
        bytes32 positionId,
        address collateralToken,
        uint256 rawCollateralAmount // token.decimals
    ) internal {
        require(positionId != bytes32(0), InvalidId(positionId));
        require(
            _isCollateralExists(collateralToken),
            CollateralNotExists(collateralToken)
        );
        require(rawCollateralAmount != 0, InvalidAmount(rawCollateralAmount));
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        uint256 collateralAmount = _collateralToWad(
            collateralToken,
            rawCollateralAmount
        );
        positionAccount.collaterals[collateralToken] += collateralAmount;
        positionAccount.activeCollaterals.add(collateralToken);
    }

    function _withdrawFromAccount(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount // 1e18
    ) internal {
        require(positionId != bytes32(0), InvalidId(positionId));
        require(
            _isCollateralExists(collateralToken),
            CollateralNotExists(collateralToken)
        );
        require(collateralAmount != 0, InvalidAmount(collateralAmount));
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        require(
            positionAccount.collaterals[collateralToken] >= collateralAmount,
            InsufficientBalance(
                positionAccount.collaterals[collateralToken],
                collateralAmount
            )
        );
        positionAccount.collaterals[collateralToken] -= collateralAmount;
        uint256 rawCollateralAmount = _collateralToRaw(
            collateralToken,
            collateralAmount
        );
        IERC20Upgradeable(collateralToken).safeTransfer(
            positionAccount.owner,
            rawCollateralAmount
        );
        require(
            _isInitialMarginSafe(positionId),
            UnsafePositionAccount(positionId, UNSAFE_INITITAL)
        );
        if (positionAccount.collaterals[collateralToken] == 0) {
            positionAccount.activeCollaterals.remove(collateralToken);
        }
    }

    function _openAccountPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory allocations
    ) internal {
        // record to position
        PositionData storage positionData = _positionAccounts[positionId]
            .positions[marketId];
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        for (uint256 i = 0; i < backedPools.length; i++) {
            if (allocations[i] == 0) {
                continue;
            }
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            uint256 price = _priceOf(marketId);
            uint256 nextSize = pool.size + allocations[i];
            if (pool.size == 0) {
                pool.entryPrice = price;
            } else {
                pool.entryPrice =
                    (pool.entryPrice * pool.size + price * allocations[i]) /
                    nextSize;
            }
            pool.size = nextSize;
        }
        positionData.lastIncreasedTime = block.timestamp;
        _positionAccounts[positionId].activeMarkets.add(marketId);
        // exceeds leverage setted by setInitialLeverage
        require(
            _isLeverageSafe(positionId),
            UnsafePositionAccount(positionId, UNSAFE_LEVERAGE)
        );
        // exceeds leverage setted by MM_INITIAL_MARGIN_RATE
        require(
            _isInitialMarginSafe(positionId),
            UnsafePositionAccount(positionId, UNSAFE_INITITAL)
        );
    }

    function _closeAccountPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory allocations
    ) internal {
        // record to position
        PositionData storage positionData = _positionAccounts[positionId]
            .positions[marketId];
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        bool isAllClosed = true;
        for (uint256 i = 0; i < backedPools.length; i++) {
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            require(allocations[i] <= pool.size, "Invalid deallocate");
            pool.size -= allocations[i];
            if (pool.size == 0) {
                pool.entryPrice = 0;
                pool.entryBorrowing = 0;
            } else {
                isAllClosed = false;
            }
        }
        if (isAllClosed) {
            positionData.lastIncreasedTime = 0;
            positionData.realizedBorrowingUsd = 0;
            _positionAccounts[positionId].activeMarkets.remove(marketId);
        }
        // should safe
        require(
            _isInitialMarginSafe(positionId),
            UnsafePositionAccount(positionId, UNSAFE_MAINTENANCE)
        );
    }

    /**
     * @dev position.collateral[] is updated in this function. but ERC20 token is not transferred yet.
     */
    function _collectFeeFromCollateral(
        bytes32 positionId,
        uint256 totalFeeUsd,
        bool shouldCollateralSufficient
    )
        internal
        returns (
            uint256 deliveredFeeUsd,
            address[] memory feeAddresses,
            uint256[] memory feeAmounts // wad
        )
    {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        feeAddresses = positionAccount.activeCollaterals.values();
        feeAmounts = new uint256[](feeAddresses.length);
        uint256 remainFeeUsd = totalFeeUsd;
        for (uint256 i = 0; i < feeAddresses.length; i++) {
            address collateral = feeAddresses[i];
            if (positionAccount.collaterals[collateral] == 0) {
                continue;
            }
            uint256 tokenPrice = _priceOf(collateral);
            require(tokenPrice > 0, "price <= 0");
            uint256 balanceUsd = (positionAccount.collaterals[collateral] *
                tokenPrice) / 1e18;
            uint256 feeUsd = MathUpgradeable.min(balanceUsd, remainFeeUsd);
            uint256 feeCollateral = (feeUsd * 1e18) / tokenPrice;
            positionAccount.collaterals[collateral] -= feeCollateral;
            remainFeeUsd -= feeUsd;
            feeAmounts[i] = feeCollateral;
            if (remainFeeUsd == 0) {
                break;
            }
        }
        if (shouldCollateralSufficient) {
            require(remainFeeUsd == 0, "Insufficient collaterals");
        }
        deliveredFeeUsd = totalFeeUsd - remainFeeUsd;
    }

    function _updateAccountBorrowingFee(
        bytes32 marketId,
        bytes32 positionId,
        uint256[] memory cumulatedBorrowingPerUsd,
        bool shouldCollateralSufficient
    )
        internal
        returns (
            uint256 borrowingFeeUsd, // note: if shouldCollateralSufficient = false, borrowingFeeUsd could <= sum(borrowingFeeUsds)
            uint256[] memory borrowingFeeUsds, // the same size as backed pools
            address[] memory feeAddresses,
            uint256[] memory feeAmounts // wad
        )
    {
        // allocate borrowing fee to collaterals
        (borrowingFeeUsd, borrowingFeeUsds) = _borrowingFeeUsd(
            positionId,
            marketId,
            cumulatedBorrowingPerUsd
        );
        (borrowingFeeUsd, feeAddresses, feeAmounts) = _collectFeeFromCollateral(
            positionId,
            borrowingFeeUsd,
            shouldCollateralSufficient
        );
        // update entryBorrowing
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        PositionData storage positionData = _positionAccounts[positionId]
            .positions[marketId];
        // foreach backed pool
        for (uint256 i = 0; i < backedPools.length; i++) {
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            if (pool.size == 0) {
                continue;
            }
            pool.entryBorrowing = cumulatedBorrowingPerUsd[i];
        }
    }

    function _updatePositionFee(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        bool shouldCollateralSufficient
    )
        internal
        returns (
            uint256 positionFeeUsd,
            address[] memory feeAddresses,
            uint256[] memory feeAmounts
        )
    {
        uint256 feeRate = _marketPositionFeeRate(marketId);
        uint256 marketPrice = _priceOf(marketId);
        uint256 value = (size * marketPrice) / 1e18;
        positionFeeUsd = (value * feeRate) / 1e18;
        (positionFeeUsd, feeAddresses, feeAmounts) = _collectFeeFromCollateral(
            positionId,
            positionFeeUsd,
            shouldCollateralSufficient
        );
    }

    function _isPositionAccountExist(
        bytes32 positionId
    ) internal view returns (bool) {
        return _positionAccounts[positionId].owner != address(0);
    }

    function _createPositionAccount(bytes32 positionId) internal {
        (address owner, ) = positionId.decodePositionId();
        _positionAccounts[positionId].owner = owner;
        _positionAccountLists[owner].add(positionId);
    }

    function _isAccountExist(bytes32 positionId) internal view returns (bool) {
        return _positionAccounts[positionId].owner != address(0);
    }

    function _collateralValue(
        bytes32 positionId
    ) internal view returns (uint256 value) {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        address[] memory collaterals = positionAccount
            .activeCollaterals
            .values();
        for (uint256 i = 0; i < collaterals.length; i++) {
            address collateral = collaterals[i];
            uint256 amount = positionAccount.collaterals[collateral];
            if (amount == 0) {
                continue;
            }
            uint256 price = _priceOf(collateral);
            value += (amount * price) / 1e18;
        }
    }

    function _positionValue(
        bytes32 positionId
    ) internal view returns (uint256 value) {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        bytes32[] memory markets = positionAccount.activeMarkets.values();
        for (uint256 i = 0; i < markets.length; i++) {
            bytes32 marketId = markets[i];
            PositionData storage data = positionAccount.positions[marketId];
            BackedPoolState[] memory backedPools = _markets[marketId].pools;
            uint256 size;
            for (uint256 j = 0; j < backedPools.length; j++) {
                address backedPool = backedPools[j].backedPool;
                PositionPoolData storage pool = data.pools[backedPool];
                size += pool.size;
            }
            if (size == 0) {
                continue;
            }
            uint256 price = _priceOf(marketId);
            value += (size * price) / 1e18;
        }
    }

    function _positionMargin(
        bytes32 positionId
    ) internal view returns (uint256 value) {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        bytes32[] memory markets = positionAccount.activeMarkets.values();
        for (uint256 i = 0; i < markets.length; i++) {
            bytes32 marketId = markets[i];
            PositionData storage positionData = positionAccount.positions[
                marketId
            ];
            BackedPoolState[] memory backedPools = _markets[marketId].pools;
            uint256 size;
            for (uint256 j = 0; j < backedPools.length; j++) {
                address backedPool = backedPools[j].backedPool;
                PositionPoolData storage pool = positionData.pools[backedPool];
                size += pool.size;
            }
            uint256 price = _priceOf(marketId);
            value += (size * price) / _maxLeverage(marketId, positionId);
        }
    }

    function _isInitialMarginSafe(
        bytes32 positionId
    ) internal view returns (bool) {
        return
            _collateralValue(positionId) >=
            _positionValue(positionId) * _marketInitialMarginRate(bytes32(0));
    }

    function _isMaintenanceMarginSafe(
        bytes32 positionId
    ) internal view returns (bool) {
        return
            _collateralValue(positionId) >=
            _positionValue(positionId) *
                _marketMaintenanceMarginRate(bytes32(0));
    }

    function _isLeverageSafe(bytes32 positionId) internal view returns (bool) {
        uint256 collateralValue = _collateralValue(positionId);
        uint256 positionMargin = _positionMargin(positionId);
        return collateralValue > positionMargin;
    }

    function _borrowingFeeUsd(
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory cumulatedBorrowingPerUsd // the same size as backed pools
    )
        internal
        view
        returns (
            uint256 borrowingFeeUsd, // total fee
            uint256[] memory borrowingFeeUsds // the same size as backed pools
        )
    {
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        PositionData storage positionData = _positionAccounts[positionId]
            .positions[marketId];
        borrowingFeeUsds = new uint256[](backedPools.length);
        for (uint256 i = 0; i < backedPools.length; i++) {
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            if (pool.size == 0) {
                continue;
            }
            uint256 feePerUsd = cumulatedBorrowingPerUsd[i] -
                pool.entryBorrowing;
            uint256 price = _priceOf(marketId);
            uint256 positionValue = (pool.size * price) / 1e18;
            uint256 feeUsd = (positionValue * feePerUsd) / 1e18;
            borrowingFeeUsds[i] = feeUsd;
            borrowingFeeUsd += feeUsd;
        }
    }

    function _maxLeverage(
        bytes32 marketId,
        bytes32 positionId
    ) internal view returns (uint256) {
        uint256 maxLeverage = _positionAccounts[positionId]
            .positions[marketId]
            .initialLeverage;
        if (maxLeverage == 0) {
            maxLeverage = _marketMaxInitialLeverage(marketId);
        }
        return maxLeverage;
    }

    function _positionPnlUsd(
        bytes32 marketId,
        bytes32 positionId,
        uint256[] memory allocations, // the same size as backed pools
        uint256 marketPrice
    )
        internal
        view
        returns (
            bool[] memory hasProfit,
            uint256[] memory poolPnlUsds // the same size as backed pools
        )
    {
        MarketInfo storage market = _markets[marketId];
        hasProfit = new bool[](market.pools.length);
        poolPnlUsds = new uint256[](market.pools.length);
        {
            // quick return if size = 0
            uint256 size;
            for (uint256 i = 0; i < allocations.length; i++) {
                size += allocations[i];
            }
            if (size == 0) {
                return (hasProfit, poolPnlUsds);
            }
        }
        PositionData storage position = _positionAccounts[positionId].positions[
            marketId
        ];
        for (uint256 i = 0; i < market.pools.length; i++) {
            address backedPool = market.pools[i].backedPool;
            PositionPoolData storage pool = position.pools[backedPool];
            require(
                allocations[i] <= pool.size,
                "positionPnl: Invalid allocation"
            );
            (hasProfit[i], poolPnlUsds[i]) = ICollateralPool(backedPool)
                .positionPnl(
                    marketId,
                    allocations[i],
                    pool.entryPrice,
                    marketPrice
                );
        }
    }
}
