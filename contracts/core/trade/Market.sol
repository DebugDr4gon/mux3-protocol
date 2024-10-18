// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/IMarket.sol";
import "../../interfaces/ICollateralPool.sol";
import "../../interfaces/IFeeDistributor.sol";
import "../Mux3FacetBase.sol";
import "../../libraries/LibExpBorrowingRate.sol";

contract Market is Mux3FacetBase, IMarket {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using LibConfigMap for mapping(bytes32 => bytes32);
    using LibTypeCast for uint256;
    using LibTypeCast for int256;

    function _openMarketPosition(
        bytes32 marketId,
        uint256[] memory allocations
    ) internal {
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        require(
            allocations.length == backedPools.length,
            "openMarket: Invalid allocation length"
        );
        for (uint256 i = 0; i < backedPools.length; i++) {
            uint256 allocation = allocations[i];
            if (allocation == 0) {
                continue;
            }
            ICollateralPool(backedPools[i].backedPool).openPosition(
                marketId,
                allocation
            );
        }
    }

    function _closeMarketPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory allocations
    ) internal {
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        require(
            allocations.length == backedPools.length,
            "closeMarket: Invalid allocation length"
        );
        PositionData storage positionData = _positionAccounts[positionId]
            .positions[marketId];
        for (uint256 i = 0; i < backedPools.length; i++) {
            address backedPool = backedPools[i].backedPool;
            PositionPoolData storage pool = positionData.pools[backedPool];
            ICollateralPool(backedPool).closePosition(
                marketId,
                allocations[i],
                pool.entryPrice
            );
        }
    }

    /**
     * @dev split x into [x1, x2, ...] (the same length as .pools)
     *      in order to equalize the new borrowingFeeRate of each pool.
     * @return allocations [amount of .pools[i]]
     */
    function _allocateLiquidity(
        bytes32 marketId,
        uint256 size
    ) internal view returns (uint256[] memory allocations) {
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        IBorrowingRate.Pool[] memory confs = new IBorrowingRate.Pool[](
            backedPools.length
        );
        uint256 price = _priceOf(marketId);
        require(price > 0, "price <= 0");
        // allocate pools according to sizeUsd
        allocations = new uint256[](backedPools.length);
        uint256 sizeUsd = (size * price) / 1e18;
        for (uint256 i = 0; i < backedPools.length; i++) {
            confs[i] = ICollateralPool(backedPools[i].backedPool)
                .makeBorrowingContext(marketId);
            confs[i].poolId = i;
        }
        IBorrowingRate.AllocateResult[]
            memory allocatedUsd = LibExpBorrowingRate.allocate2(
                confs,
                sizeUsd.toInt256()
            );
        // convert sizeUsd back to size
        for (uint256 i = 0; i < allocatedUsd.length; i++) {
            uint256 poolId = allocatedUsd[i].poolId;
            require(poolId < backedPools.length, "Invalid poolId");
            uint256 sizeForPoolUsd = allocatedUsd[i].xi.toUint256();
            uint256 sizeForPool = (sizeForPoolUsd * 1e18) / price;
            allocations[poolId] = sizeForPool;
        }
        // align to lotSize
        uint256 lotSize = _marketLotSize(marketId);
        allocations = LibExpBorrowingRate.alignAllocationToLotSize(
            size,
            allocations,
            lotSize
        );
        uint256 sizeDoubleCheck = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            sizeDoubleCheck += allocations[i];
        }
        require(sizeDoubleCheck == size, "Allocation size mismatch"); // probably implies abug
    }

    /**
     * @dev split x into [x1, x2, ...] (the same length as .pools)
     *      according to the factor of .pools[i].totalSize
     * @return allocations [amount of .pools[i]]
     */
    function _deallocateLiquidity(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) internal view returns (uint256[] memory allocations) {
        PositionData storage positionData = _positionAccounts[positionId]
            .positions[marketId];
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        allocations = new uint256[](backedPools.length);
        // according to the proportion of my positions in each pool
        uint256 totalSize = 0;
        for (uint256 i = 0; i < backedPools.length; i++) {
            uint256 sizeForPool = positionData
                .pools[backedPools[i].backedPool]
                .size;
            totalSize += sizeForPool;
        }
        require(size <= totalSize, "size > position size");
        if (totalSize > 0) {
            for (uint256 i = 0; i < backedPools.length; i++) {
                uint256 sizeForPool = positionData
                    .pools[backedPools[i].backedPool]
                    .size;
                allocations[i] = (size * sizeForPool) / totalSize;
            }
        }
        // align to lotSize
        uint256 lotSize = _marketLotSize(marketId);
        allocations = LibExpBorrowingRate.alignAllocationToLotSize(
            size,
            allocations,
            lotSize
        );
        uint256 sizeDoubleCheck = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            sizeDoubleCheck += allocations[i];
        }
        require(sizeDoubleCheck == size, "Allocation size mismatch"); // probably implies a bug
    }

    function _updateMarketBorrowing(
        bytes32 marketId
    ) internal returns (uint256[] memory newCumulatedBorrowingPerUsd) {
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        newCumulatedBorrowingPerUsd = new uint256[](backedPools.length);
        for (uint256 i = 0; i < backedPools.length; i++) {
            newCumulatedBorrowingPerUsd[i] = ICollateralPool(
                backedPools[i].backedPool
            ).updateMarketBorrowing(marketId);
        }
    }

    function _dispatchFee(
        address trader,
        bytes32 marketId,
        bytes32 positionId,
        address[] memory feeAddresses,
        uint256[] memory feeAmounts, // [amount foreach feeAddresses], decimals = 18
        // note: allocation only represents a proportional relationship.
        //       the sum of allocations does not necessarily have to be consistent with the total value.
        uint256[] memory allocations // [amount foreach backed pools], decimals = 18.
    ) internal {
        uint256 length = feeAddresses.length;
        require(
            length == feeAmounts.length,
            "feeAddresses and feeAmounts mismatched"
        );
        require(
            allocations.length == _markets[marketId].pools.length,
            "allocations and backed pools mismatched"
        );
        for (uint256 i = 0; i < length; i++) {
            uint256 wad = feeAmounts[i];
            if (wad == 0) {
                continue;
            }
            emit CollectFee(feeAddresses[i], wad);
        }
        address feeDistributor = _feeDistributor();
        if (feeDistributor == address(0)) {
            return;
        }
        for (uint256 i = 0; i < length; i++) {
            uint256 wad = feeAmounts[i];
            if (wad == 0) {
                continue;
            }
            IERC20Upgradeable(feeAddresses[i]).safeTransfer(
                feeDistributor,
                _collateralToRaw(feeAddresses[i], wad)
            );
        }
        IFeeDistributor(feeDistributor).updatePositionFees(
            trader,
            marketId,
            positionId,
            feeAddresses,
            feeAmounts,
            allocations
        );
    }

    function _realizeProfitAndLoss(
        bytes32 marketId,
        bytes32 positionId,
        bool[] memory hasProfits,
        uint256[] memory poolPnlUsds,
        bool isThrowBankrupt
    ) internal returns (uint256[] memory newPoolPnlUsds) {
        BackedPoolState[] memory backedPools = _markets[marketId].pools;
        require(
            backedPools.length == poolPnlUsds.length &&
                backedPools.length == hasProfits.length,
            "poolPnlUsds mismatched"
        );
        newPoolPnlUsds = new uint256[](backedPools.length);
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // take profit first
        for (uint256 i = 0; i < poolPnlUsds.length; i++) {
            if (!hasProfits[i] || poolPnlUsds[i] == 0) {
                continue;
            }
            newPoolPnlUsds[i] = _realizeProfit(
                backedPools[i].backedPool,
                poolPnlUsds[i],
                positionAccount
            );
        }
        // then realize loss
        for (uint256 i = 0; i < poolPnlUsds.length; i++) {
            if (hasProfits[i] || poolPnlUsds[i] == 0) {
                continue;
            }
            newPoolPnlUsds[i] = _realizeLoss(
                backedPools[i].backedPool,
                poolPnlUsds[i],
                positionAccount,
                isThrowBankrupt
            );
        }
    }

    function _realizeProfit(
        address backedPool,
        uint256 poolPnlUsd,
        PositionAccountInfo storage positionAccount
    ) private returns (uint256 deliveredPoolPnlUsd) {
        (address collateralToken, uint256 collateralAmount) = ICollateralPool(
            backedPool
        ).realizeProfit(poolPnlUsd);
        positionAccount.collaterals[collateralToken] += collateralAmount;
        positionAccount.activeCollaterals.add(collateralToken);
        deliveredPoolPnlUsd = poolPnlUsd;
    }

    /**
     * @dev transfer trader collateral to backed pool
     */
    function _realizeLoss(
        address backedPool,
        uint256 poolPnlUsd,
        PositionAccountInfo storage positionAccount,
        bool isThrowBankrupt
    ) private returns (uint256 deliveredPoolPnlUsd) {
        address[] memory collateralAddresses = positionAccount
            .activeCollaterals
            .values();
        uint256 remainPnlUsd = poolPnlUsd;
        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            address collateral = collateralAddresses[i];
            uint256 tokenPrice = _priceOf(collateral);
            require(tokenPrice > 0, "price <= 0");
            // deduce from collateral
            uint256 wad = MathUpgradeable.min(
                positionAccount.collaterals[collateral],
                MathUpgradeable.ceilDiv(remainPnlUsd * 1e18, tokenPrice)
            );
            if (wad == 0) {
                continue;
            }
            positionAccount.collaterals[collateral] -= wad;
            uint256 realizedPnlUsd = MathUpgradeable.min(
                (wad * tokenPrice) / 1e18,
                remainPnlUsd
            );
            // send them to backed pool
            uint256 raw = _collateralToRaw(collateral, wad);
            IERC20Upgradeable(collateral).safeTransfer(backedPool, raw);
            ICollateralPool(backedPool).realizeLoss(collateral, raw);
            // update remain
            remainPnlUsd -= realizedPnlUsd;
            if (remainPnlUsd == 0) {
                break;
            }
        }
        if (isThrowBankrupt) {
            require(remainPnlUsd == 0, "Insufficient collaterals");
        }
        deliveredPoolPnlUsd = poolPnlUsd - remainPnlUsd;
    }
}
