// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../../libraries/LibCodec.sol";
import "../../libraries/LibEthUnwrapper.sol";
import "../Mux3FacetBase.sol";

contract PositionAccount is Mux3FacetBase {
    using LibTypeCast for uint256;
    using LibTypeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using LibConfigMap for mapping(bytes32 => bytes32);

    function _setInitialLeverage(bytes32 positionId, bytes32 marketId, uint256 initialLeverage) internal {
        require(initialLeverage > 0, InitialLeverageOutOfRange(initialLeverage, 0));
        uint256 imr = _marketInitialMarginRate(marketId);
        require(imr > 0, EssentialConfigNotSet("MM_INITIAL_MARGIN_RATE"));
        uint256 maxLeverage = 1e36 / imr;
        require(initialLeverage <= maxLeverage, InitialLeverageOutOfRange(initialLeverage, maxLeverage));
        _positionAccounts[positionId].positions[marketId].initialLeverage = initialLeverage;
    }

    function _traderMaxInitialLeverage(bytes32 positionId, bytes32 marketId) internal view returns (uint256 leverage) {
        leverage = _positionAccounts[positionId].positions[marketId].initialLeverage;
        require(leverage > 0, EssentialConfigNotSet("setInitialLeverage"));
    }

    // OrderBook should transfer collateralToken to this contract
    function _depositToAccount(
        bytes32 positionId,
        address collateralToken,
        uint256 rawCollateralAmount // token.decimals
    ) internal {
        require(positionId != bytes32(0), InvalidId(positionId));
        require(_isCollateralExists(collateralToken), CollateralNotExists(collateralToken));
        require(rawCollateralAmount != 0, InvalidAmount(rawCollateralAmount));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        uint256 collateralAmount = _collateralToWad(collateralToken, rawCollateralAmount);
        positionAccount.collaterals[collateralToken] += collateralAmount;
        EnumerableSetUpgradeable.AddressSet storage activeCollaterals = positionAccount.activeCollaterals;
        if (!activeCollaterals.contains(collateralToken)) {
            require(
                activeCollaterals.length() < MAX_COLLATERALS_PER_POSITION_ACCOUNT,
                CapacityExceeded(MAX_COLLATERALS_PER_POSITION_ACCOUNT, activeCollaterals.length(), 1)
            );
            activeCollaterals.add(collateralToken);
        }
    }

    function _withdrawFromAccount(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount, // 1e18
        bool isUnwrapWeth
    ) internal {
        require(positionId != bytes32(0), InvalidId(positionId));
        require(_isCollateralExists(collateralToken), CollateralNotExists(collateralToken));
        require(collateralAmount != 0, InvalidAmount(collateralAmount));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        require(
            positionAccount.collaterals[collateralToken] >= collateralAmount,
            InsufficientBalance(positionAccount.collaterals[collateralToken], collateralAmount)
        );
        positionAccount.collaterals[collateralToken] -= collateralAmount;
        uint256 rawCollateralAmount = _collateralToRaw(collateralToken, collateralAmount);
        if (collateralToken == _weth && isUnwrapWeth) {
            LibEthUnwrapper.unwrap(_weth, payable(positionAccount.owner), rawCollateralAmount);
        } else {
            IERC20Upgradeable(collateralToken).safeTransfer(positionAccount.owner, rawCollateralAmount);
        }
        // auto clear
        if (positionAccount.collaterals[collateralToken] == 0) {
            positionAccount.activeCollaterals.remove(collateralToken);
        }
    }

    function _openAccountPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory allocations, // the same size as backed pools
        uint256[] memory cumulatedBorrowingPerUsd // the same size as backed pools
    ) internal {
        // record to position
        PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        for (uint256 i = 0; i < backedPools.length; i++) {
            if (allocations[i] == 0) {
                continue;
            }
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            uint256 price = _priceOf(_marketOracleId(marketId));
            uint256 nextSize = pool.size + allocations[i];
            if (pool.size == 0) {
                pool.entryPrice = price;
            } else {
                pool.entryPrice = (pool.entryPrice * pool.size + price * allocations[i]) / nextSize;
            }
            pool.size = nextSize;
            pool.entryBorrowing = cumulatedBorrowingPerUsd[i];
        }
        positionData.lastIncreasedTime = block.timestamp;
        if (!_positionAccounts[positionId].activeMarkets.contains(marketId)) {
            require(
                _positionAccounts[positionId].activeMarkets.length() < MAX_MARKETS_PER_POSITION_ACCOUNT,
                CapacityExceeded(
                    MAX_MARKETS_PER_POSITION_ACCOUNT,
                    _positionAccounts[positionId].activeMarkets.length(),
                    1
                )
            );
            _positionAccounts[positionId].activeMarkets.add(marketId);
        }
    }

    function _closeAccountPosition(bytes32 positionId, bytes32 marketId, uint256[] memory allocations) internal {
        // record to position
        PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
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
        // auto clear
        if (isAllClosed) {
            positionData.lastIncreasedTime = 0;
            positionData.realizedBorrowingUsd = 0;
            _positionAccounts[positionId].activeMarkets.remove(marketId);
        }
    }

    /**
     * @dev deduct collateral until its value equals totalFeeUsd
     *
     *      note: position.collateral[] is updated in this function. but ERC20 token is not transferred yet.
     *
     * @param lastConsumedToken optional. try to avoid consuming this token if possible
     */
    function _collectFeeFromCollateral(
        bytes32 positionId,
        uint256 totalFeeUsd,
        bool shouldCollateralSufficient,
        address lastConsumedToken
    )
        internal
        returns (
            uint256 deliveredFeeUsd,
            address[] memory feeAddresses,
            uint256[] memory feeAmounts // wad
        )
    {
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        feeAddresses = _activeCollateralsWithLastWithdraw(positionId, lastConsumedToken);
        feeAmounts = new uint256[](feeAddresses.length);
        uint256 remainFeeUsd = totalFeeUsd;
        for (uint256 i = 0; i < feeAddresses.length; i++) {
            address collateral = feeAddresses[i];
            if (positionAccount.collaterals[collateral] == 0) {
                continue;
            }
            uint256 tokenPrice = _priceOf(collateral);
            uint256 balanceUsd = (positionAccount.collaterals[collateral] * tokenPrice) / 1e18;
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
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory cumulatedBorrowingPerUsd,
        bool shouldCollateralSufficient,
        address lastConsumedToken
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
        (borrowingFeeUsd, borrowingFeeUsds) = _borrowingFeeUsd(positionId, marketId, cumulatedBorrowingPerUsd);
        (borrowingFeeUsd, feeAddresses, feeAmounts) = _collectFeeFromCollateral(
            positionId,
            borrowingFeeUsd,
            shouldCollateralSufficient,
            lastConsumedToken
        );
        // update entryBorrowing
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
        for (uint256 i = 0; i < backedPools.length; i++) {
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            if (pool.size == 0) {
                continue;
            }
            pool.entryBorrowing = cumulatedBorrowingPerUsd[i];
        }
        // update realizedBorrowingUsd
        positionData.realizedBorrowingUsd += borrowingFeeUsd;
    }

    function _updatePositionFee(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        bool isLiquidating,
        bool shouldCollateralSufficient,
        address lastConsumedToken
    ) internal returns (uint256 positionFeeUsd, address[] memory feeAddresses, uint256[] memory feeAmounts) {
        uint256 feeRate;
        if (isLiquidating) {
            feeRate = _marketLiquidationFeeRate(marketId);
        } else {
            feeRate = _marketPositionFeeRate(marketId);
        }
        uint256 marketPrice = _priceOf(_marketOracleId(marketId));
        uint256 value = (size * marketPrice) / 1e18;
        positionFeeUsd = (value * feeRate) / 1e18;
        (positionFeeUsd, feeAddresses, feeAmounts) = _collectFeeFromCollateral(
            positionId,
            positionFeeUsd,
            shouldCollateralSufficient,
            lastConsumedToken
        );
    }

    function _isPositionAccountExist(bytes32 positionId) internal view returns (bool) {
        return _positionAccounts[positionId].owner != address(0);
    }

    function _createPositionAccount(bytes32 positionId) internal {
        (address owner, ) = LibCodec.decodePositionId(positionId);
        _positionAccounts[positionId].owner = owner;
        if (!_positionAccountLists[owner].contains(positionId)) {
            require(
                _positionAccountLists[owner].length() < MAX_POSITION_ACCOUNT_PER_TRADER,
                CapacityExceeded(MAX_POSITION_ACCOUNT_PER_TRADER, _positionAccountLists[owner].length(), 1)
            );
            _positionAccountLists[owner].add(positionId);
        }
    }

    function _isAccountExist(bytes32 positionId) internal view returns (bool) {
        return _positionAccounts[positionId].owner != address(0);
    }

    function _collateralValue(bytes32 positionId) internal view returns (uint256 value) {
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        address[] memory collaterals = positionAccount.activeCollaterals.values();
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

    enum MarginType {
        MARKET_IM, // marketPrice * size * imr
        MARKET_MM, // marketPrice * size * mmr
        ENTRY_LEVERAGE // entryPrice * size / traderLeverage
    }

    function _positionMargin(bytes32 positionId, MarginType marginType) internal view returns (uint256 marginUsd) {
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        bytes32[] memory markets = positionAccount.activeMarkets.values();
        for (uint256 i = 0; i < markets.length; i++) {
            bytes32 marketId = markets[i];
            PositionData storage positionData = positionAccount.positions[marketId];
            BackedPoolState[] memory backedPools = _markets[marketId].pools;
            // position size
            uint256 size;
            uint256 entryValue;
            for (uint256 j = 0; j < backedPools.length; j++) {
                address backedPool = backedPools[j].backedPool;
                PositionPoolData storage pool = positionData.pools[backedPool];
                size += pool.size;
                entryValue += (pool.size * pool.entryPrice) / 1e18;
            }
            if (size == 0) {
                continue;
            }
            // margin
            uint256 value;
            if (marginType == MarginType.MARKET_IM) {
                uint256 price = _priceOf(_marketOracleId(marketId));
                value = (size * price) / 1e18;
                value = (value * _marketInitialMarginRate(marketId)) / 1e18;
            } else if (marginType == MarginType.MARKET_MM) {
                uint256 price = _priceOf(_marketOracleId(marketId));
                value = (size * price) / 1e18;
                value = (value * _marketMaintenanceMarginRate(marketId)) / 1e18;
            } else if (marginType == MarginType.ENTRY_LEVERAGE) {
                value = (entryValue * 1e18) / _traderMaxInitialLeverage(positionId, marketId);
            }
            marginUsd += value;
        }
    }

    /**
     * @dev check if marginBalance >= marketPrice * size * initialMarginRate
     *
     *      note: this function does not calculate borrowing fee. so make sure
     *            to update borrowing fee before calling this function.
     */
    function _isInitialMarginSafe(bytes32 positionId) internal view returns (bool) {
        uint256 positionMargin = _positionMargin(positionId, MarginType.MARKET_IM);
        if (positionMargin == 0) {
            return true;
        }
        int256 marginBalance = _marginBalance(positionId);
        if (marginBalance < 0) {
            return false;
        }
        return uint256(marginBalance) >= positionMargin;
    }

    /**
     * @dev check if marginBalance >= marketPrice * size * maintenanceMarginRate
     */
    function _isMaintenanceMarginSafe(
        bytes32 positionId,
        uint256 pendingBorrowingFeeUsd // if borrowing fee is not deducted from collaterals yet, pass it here
    ) internal view returns (bool) {
        uint256 positionMargin = _positionMargin(positionId, MarginType.MARKET_MM);
        positionMargin += pendingBorrowingFeeUsd;
        if (positionMargin == 0) {
            return true;
        }
        int256 marginBalance = _marginBalance(positionId);
        if (marginBalance < 0) {
            return false;
        }
        return uint256(marginBalance) >= positionMargin;
    }

    /**
     * @dev check if collateralValue >= entryPrice * size / traderMaxLeverage
     *
     *      note: this function does not calculate borrowing fee. so make sure
     *            to update borrowing fee before calling this function.
     */
    function _isLeverageSafe(bytes32 positionId) internal view returns (bool) {
        uint256 positionMargin = _positionMargin(positionId, MarginType.ENTRY_LEVERAGE);
        if (positionMargin == 0) {
            return true;
        }
        uint256 collateralValue = _collateralValue(positionId);
        return collateralValue >= positionMargin;
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
        PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
        borrowingFeeUsds = new uint256[](backedPools.length);
        for (uint256 i = 0; i < backedPools.length; i++) {
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            if (pool.size == 0) {
                continue;
            }
            uint256 price = _priceOf(_marketOracleId(marketId));
            uint256 positionValue = (pool.size * price) / 1e18;
            uint256 feePerUsd = cumulatedBorrowingPerUsd[i] - pool.entryBorrowing;
            uint256 feeUsd = (positionValue * feePerUsd) / 1e18;
            borrowingFeeUsds[i] = feeUsd;
            borrowingFeeUsd += feeUsd;
        }
    }

    function _positionPnlUsd(
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory allocations, // the same size as backed pools
        uint256 marketPrice
    )
        internal
        view
        returns (
            int256[] memory poolPnlUsds // the same size as backed pools
        )
    {
        MarketInfo storage market = _markets[marketId];
        poolPnlUsds = new int256[](market.pools.length);
        {
            // quick return if size = 0
            uint256 size;
            for (uint256 i = 0; i < allocations.length; i++) {
                size += allocations[i];
            }
            if (size == 0) {
                return poolPnlUsds;
            }
        }
        PositionData storage position = _positionAccounts[positionId].positions[marketId];
        for (uint256 i = 0; i < market.pools.length; i++) {
            address backedPool = market.pools[i].backedPool;
            PositionPoolData storage pool = position.pools[backedPool];
            require(allocations[i] <= pool.size, "positionPnl: Invalid allocation");
            poolPnlUsds[i] = ICollateralPool(backedPool).positionPnl(
                marketId,
                allocations[i],
                pool.entryPrice,
                marketPrice
            );
        }
    }

    /**
     * @dev marginBalance = collateral + pnl
     *
     *      note: this function does not calculate borrowing fee. so make sure
     *            to update borrowing fee before calling this function.
     */
    function _marginBalance(bytes32 positionId) internal view returns (int256 marginBalance) {
        marginBalance = _collateralValue(positionId).toInt256();
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        uint256 marketLength = positionAccount.activeMarkets.length();
        for (uint256 i = 0; i < marketLength; i++) {
            bytes32 marketId = positionAccount.activeMarkets.at(i);
            BackedPoolState[] memory backedPools = _markets[marketId].pools;
            PositionData storage positionData = positionAccount.positions[marketId];
            for (uint256 j = 0; j < backedPools.length; j++) {
                address backedPool = backedPools[j].backedPool;
                PositionPoolData storage pool = positionData.pools[backedPool];
                if (pool.size == 0) {
                    continue;
                }
                int256 pnlUsd = ICollateralPool(backedPool).positionPnl(
                    marketId,
                    pool.size,
                    pool.entryPrice,
                    _priceOf(_marketOracleId(marketId))
                );
                marginBalance += pnlUsd;
            }
        }
    }
}
