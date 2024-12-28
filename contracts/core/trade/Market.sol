// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "../../interfaces/IMux3FeeDistributor.sol";
import "../../libraries/LibExpBorrowingRate.sol";
import "../Mux3FacetBase.sol";

contract Market is Mux3FacetBase, IMarket {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using LibConfigMap for mapping(bytes32 => bytes32);
    using LibTypeCast for uint256;
    using LibTypeCast for int256;
    using LibTypeCast for bytes32;

    function _openMarketPosition(bytes32 marketId, uint256[] memory allocations, uint256 price) internal {
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        // open position in each pool
        // note: allocations already implies capacity for each pool
        require(
            allocations.length == backedPools.length,
            AllocationLengthMismatch(allocations.length, backedPools.length)
        );
        for (uint256 i = 0; i < backedPools.length; i++) {
            uint256 allocation = allocations[i];
            if (allocation == 0) {
                continue;
            }
            address backedPool = backedPools[i].backedPool;
            ICollateralPool(backedPool).openPosition(marketId, allocation, price);
        }
        // total position limit
        {
            uint256 openInterestUsd = 0;
            for (uint256 i = 0; i < backedPools.length; i++) {
                address backedPool = backedPools[i].backedPool;
                MarketState memory marketForPool = ICollateralPool(backedPool).marketState(marketId);
                uint256 sizeUsd = (marketForPool.totalSize * price) / 1e18;
                openInterestUsd += sizeUsd;
            }
            uint256 capUsd = _marketOpenInterestCap(marketId);
            require(openInterestUsd <= capUsd, MarketFull());
        }
    }

    function _closeMarketPosition(bytes32 positionId, bytes32 marketId, uint256[] memory allocations) internal {
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        require(
            allocations.length == backedPools.length,
            AllocationLengthMismatch(allocations.length, backedPools.length)
        );
        PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
        for (uint256 i = 0; i < backedPools.length; i++) {
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            ICollateralPool(backedPool).closePosition(marketId, allocations[i], pool.entryPrice);
        }
    }

    /**
     * @dev Split x into [x1, x2, ...] (the same length as .pools)
     *      in order to equalize the new borrowingFeeRate of each pool.
     * @return allocations [amount of .pools[i]]
     */
    function _allocateLiquidity(bytes32 marketId, uint256 size) internal view returns (uint256[] memory allocations) {
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        uint256 price = _priceOf(_marketOracleId(marketId));
        // allocate pools according to sizeUsd
        IBorrowingRate.AllocatePool[] memory confs = new IBorrowingRate.AllocatePool[](backedPools.length);
        uint256 confLength = 0; // count of pools that participate in allocation
        for (uint256 i = 0; i < backedPools.length; i++) {
            confs[confLength] = ICollateralPool(backedPools[i].backedPool).makeBorrowingContext(marketId);
            confs[confLength].poolId = i;
            // skip pools with no liquidity
            if (confs[confLength].poolSizeUsd <= 0) {
                continue;
            }
            // skip draining pools
            if (confs[confLength].isDraining) {
                continue;
            }
            confLength++;
        }
        uint256 sizeUsd = (size * price) / 1e18;
        IBorrowingRate.AllocateResult[] memory allocatedUsd = LibExpBorrowingRate.allocate2(
            // note: "x" is usd in LibExpBorrowingRate.allocation series functions
            confs,
            confLength,
            sizeUsd.toInt256()
        );
        // convert sizeUsd back to size
        allocations = new uint256[](backedPools.length);
        for (uint256 i = 0; i < allocatedUsd.length; i++) {
            uint256 poolId = allocatedUsd[i].poolId;
            require(poolId < backedPools.length, OutOfBound(poolId, backedPools.length));
            uint256 sizeForPoolUsd = allocatedUsd[i].xi.toUint256();
            uint256 sizeForPool = (sizeForPoolUsd * 1e18) / price;
            allocations[poolId] = sizeForPool;
        }
        // align to lotSize
        uint256 lotSize = _marketLotSize(marketId);
        allocations = LibExpBorrowingRate.alignAllocationToLotSize(size, allocations, lotSize);
        uint256 sizeDoubleCheck = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            sizeDoubleCheck += allocations[i];
        }
        require(sizeDoubleCheck == size, AllocationPositionMismatch(sizeDoubleCheck, size));
    }

    /**
     * @dev Split x into [x1, x2, ...] (the same length as .pools)
     *      according to the factor of .pools[i].totalSize
     * @return allocations [amount of .pools[i]]
     */
    function _deallocateLiquidity(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) internal view returns (uint256[] memory allocations) {
        PositionData storage positionData = _positionAccounts[positionId].positions[marketId];
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        // deallocate
        IBorrowingRate.DeallocatePool[] memory confs = new IBorrowingRate.DeallocatePool[](backedPools.length);
        uint256 totalSize = 0;
        for (uint256 i = 0; i < backedPools.length; i++) {
            address backedPool = backedPools[i].backedPool;
            confs[i].poolId = i;
            uint256 sizeForPool = positionData.pools[backedPool].size;
            confs[i].mySizeForPool = sizeForPool.toInt256();
            totalSize += sizeForPool;
        }
        require(size <= totalSize, InvalidCloseSize(size, totalSize));
        IBorrowingRate.DeallocateResult[] memory deallocates = LibExpBorrowingRate.deallocate2(
            confs,
            // note: "x" is NOT necessarily usd in LibExpBorrowingRate.deallocation series functions.
            //       in deallocate, we use size instead of sizeUsd.
            size.toInt256()
        );
        // convert sizeUsd back to size
        allocations = new uint256[](backedPools.length);
        for (uint256 i = 0; i < deallocates.length; i++) {
            uint256 poolId = deallocates[i].poolId;
            require(poolId < backedPools.length, OutOfBound(poolId, backedPools.length));
            uint256 sizeForPool = deallocates[i].xi.toUint256();
            allocations[poolId] = sizeForPool;
        }
        // align to lotSize
        uint256 lotSize = _marketLotSize(marketId);
        allocations = LibExpBorrowingRate.alignAllocationToLotSize(size, allocations, lotSize);
        uint256 sizeDoubleCheck = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            sizeDoubleCheck += allocations[i];
        }
        require(sizeDoubleCheck == size, AllocationPositionMismatch(sizeDoubleCheck, size));
    }

    function _updateMarketBorrowing(bytes32 marketId) internal returns (uint256[] memory newCumulatedBorrowingPerUsd) {
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        newCumulatedBorrowingPerUsd = new uint256[](backedPools.length);
        for (uint256 i = 0; i < backedPools.length; i++) {
            newCumulatedBorrowingPerUsd[i] = ICollateralPool(backedPools[i].backedPool).updateMarketBorrowing(marketId);
        }
    }

    function _dispatchFee(
        address trader,
        bytes32 marketId,
        address[] memory feeAddresses,
        uint256[] memory feeAmounts, // [amount foreach feeAddresses], decimals = 18
        // note: allocation only represents a proportional relationship.
        //       the sum of allocations does not necessarily have to be consistent with the total value.
        uint256[] memory allocations, // [amount foreach backed pools], decimals = 18.
        bool isUnwrapWeth
    ) internal {
        uint256 feeLength = feeAddresses.length;
        require(feeLength == feeAmounts.length, AllocationLengthMismatch(feeLength, feeAmounts.length));
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        uint256 poolLength = backedPools.length;
        require(allocations.length == poolLength, AllocationLengthMismatch(allocations.length, poolLength));
        address[] memory backedPoolAddresses = new address[](poolLength);
        for (uint256 pi = 0; pi < poolLength; pi++) {
            backedPoolAddresses[pi] = backedPools[pi].backedPool;
        }
        address feeDistributor = _feeDistributor();
        uint256[] memory rawFeeAmounts = new uint256[](feeLength);
        for (uint256 fi = 0; fi < feeLength; fi++) {
            uint256 wad = feeAmounts[fi];
            if (wad == 0) {
                continue;
            }
            emit CollectFee(feeAddresses[fi], wad);
            uint256 raw = _collateralToRaw(feeAddresses[fi], wad);
            if (raw == 0) {
                continue;
            }
            IERC20Upgradeable(feeAddresses[fi]).safeTransfer(feeDistributor, raw);
            rawFeeAmounts[fi] = raw;
        }
        IMux3FeeDistributor(feeDistributor).updatePositionFees(
            trader,
            feeAddresses,
            rawFeeAmounts,
            backedPoolAddresses,
            allocations,
            isUnwrapWeth
        );
    }

    function _realizeProfitAndLoss(
        bytes32 positionId,
        bytes32 marketId,
        int256[] memory poolPnlUsds,
        bool isThrowBankrupt,
        address lastConsumedToken
    ) internal returns (int256[] memory newPoolPnlUsds) {
        BackedPoolState[] storage backedPools = _markets[marketId].pools;
        require(
            backedPools.length == poolPnlUsds.length,
            AllocationLengthMismatch(backedPools.length, poolPnlUsds.length)
        );
        newPoolPnlUsds = new int256[](backedPools.length);
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        // take profit first
        for (uint256 i = 0; i < poolPnlUsds.length; i++) {
            if (poolPnlUsds[i] <= 0) {
                continue;
            }
            newPoolPnlUsds[i] = _realizeProfit(backedPools[i].backedPool, poolPnlUsds[i], positionAccount);
        }
        // then realize loss
        for (uint256 i = 0; i < poolPnlUsds.length; i++) {
            if (poolPnlUsds[i] >= 0) {
                continue;
            }
            newPoolPnlUsds[i] = _realizeLoss(
                positionId,
                backedPools[i].backedPool,
                poolPnlUsds[i],
                isThrowBankrupt,
                lastConsumedToken
            );
        }
    }

    function _realizeProfit(
        address backedPool,
        int256 poolPnlUsd, // positive means profit
        PositionAccountInfo storage positionAccount
    )
        private
        returns (
            int256 deliveredPoolPnlUsd // positive means profit
        )
    {
        require(poolPnlUsd >= 0);
        (address collateralToken, uint256 collateralAmount) = ICollateralPool(backedPool).realizeProfit(
            uint256(poolPnlUsd) // positive wad
        );
        if (collateralAmount > 0) {
            positionAccount.collaterals[collateralToken] += collateralAmount;
            // probably exceeds MAX_COLLATERALS_PER_POSITION_ACCOUNT. but we can not stop closePosition
            positionAccount.activeCollaterals.add(collateralToken);
        }
        deliveredPoolPnlUsd = LibTypeCast.toInt256((collateralAmount * _priceOf(collateralToken)) / 1e18);
    }

    /**
     * @dev Transfer trader collateral to backed pool
     *
     * @param lastConsumedToken optional. try to avoid consuming this token if possible
     */
    function _realizeLoss(
        bytes32 positionId,
        address backedPool,
        int256 poolPnlUsd, // negated means loss
        bool isThrowBankrupt,
        address lastConsumedToken
    )
        private
        returns (
            int256 deliveredPoolPnlUsd // negated means loss
        )
    {
        require(poolPnlUsd <= 0);
        address[] memory collateralAddresses = _activeCollateralsWithLastWithdraw(positionId, lastConsumedToken);
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        uint256 remainPnlUsd = poolPnlUsd.negInt256(); // convert to positive wad
        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            address collateral = collateralAddresses[i];
            uint256 tokenPrice = _priceOf(collateral);
            // deduce from collateral
            uint256 wad = MathUpgradeable.min(
                positionAccount.collaterals[collateral],
                MathUpgradeable.ceilDiv(remainPnlUsd * 1e18, tokenPrice)
            );
            if (wad == 0) {
                continue;
            }
            positionAccount.collaterals[collateral] -= wad;
            if (positionAccount.collaterals[collateral] == 0) {
                positionAccount.activeCollaterals.remove(collateral);
            }
            uint256 realizedPnlUsd = MathUpgradeable.min((wad * tokenPrice) / 1e18, remainPnlUsd);
            // send them to backed pool
            uint256 raw = _collateralToRaw(collateral, wad);
            if (raw > 0) {
                IERC20Upgradeable(collateral).safeTransfer(backedPool, raw);
                ICollateralPool(backedPool).realizeLoss(collateral, raw);
            }
            // update remain
            remainPnlUsd -= realizedPnlUsd;
            if (remainPnlUsd == 0) {
                break;
            }
        }
        if (isThrowBankrupt) {
            require(remainPnlUsd == 0, InsufficientCollateralUsd(remainPnlUsd, 0));
        }
        deliveredPoolPnlUsd = poolPnlUsd + remainPnlUsd.toInt256();
    }

    /**
    /**
     * @dev reallocate between two pools by:
     *      1. Close position from fromPool at market price
     *      2. Transfer realized PnL to toPool
     *      3. Open position in toPool at fromPool's old entry price
     *      The two AUMs remain the same
     */
    function _reallocateMarketPosition(
        bytes32 marketId,
        address fromPool,
        address toPool,
        uint256 size,
        uint256 fromPoolOldEntryPrice,
        int256 fromPoolPnlUsd
    ) internal {
        // transfer positions
        ICollateralPool(fromPool).closePosition(marketId, size, fromPoolOldEntryPrice);
        ICollateralPool(toPool).openPosition(marketId, size, fromPoolOldEntryPrice); // usually uses market price, but in this case uses trader's other entry price
        // settle pnl between pools
        if (fromPoolPnlUsd == 0) {
            // pass
        } else if (fromPoolPnlUsd > 0) {
            // if profit, transfer fromPool => toPool
            (address collateralToken, uint256 wad) = ICollateralPool(fromPool).realizeProfit(
                uint256(fromPoolPnlUsd) // positive wad
            );
            uint256 raw = _collateralToRaw(collateralToken, wad);
            if (raw > 0) {
                IERC20Upgradeable(collateralToken).safeTransfer(toPool, raw);
                ICollateralPool(toPool).realizeLoss(collateralToken, raw);
            }
        } else {
            // if loss, transfer toPool => fromPool
            (address collateralToken, uint256 wad) = ICollateralPool(toPool).realizeProfit(
                fromPoolPnlUsd.negInt256() // convert to positive wad
            );
            uint256 raw = _collateralToRaw(collateralToken, wad);
            if (raw > 0) {
                IERC20Upgradeable(collateralToken).safeTransfer(fromPool, raw);
                ICollateralPool(fromPool).realizeLoss(collateralToken, raw);
            }
        }
    }
}
