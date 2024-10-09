// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/IMarket.sol";
import "../../interfaces/ICollateralPool.sol";
import "../../interfaces/IFeeDistributor.sol";
import "../Mux3FacetBase.sol";

contract Market is Mux3FacetBase, IMarket {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using LibConfigTable for ConfigTable;

    function _openMarketPosition(
        bytes32 marketId,
        uint256[] memory allocations
    ) internal {
        for (uint256 i = 0; i < _markets[marketId].pools.length; i++) {
            uint256 allocation = allocations[i];
            if (allocation == 0) {
                continue;
            }
            ICollateralPool(_markets[marketId].pools[i].backedPool)
                .openPosition(marketId, allocation);
            _markets[marketId].pools[i].totalSize += allocation;
        }
    }

    function _closeMarketPosition(
        bytes32 marketId,
        uint256[] memory allocations
    ) internal {
        require(
            allocations.length == _markets[marketId].pools.length,
            "Invalid allocation"
        );
        for (uint256 i = 0; i < _markets[marketId].pools.length; i++) {
            uint256 allocation = allocations[i];
            ICollateralPool(_markets[marketId].pools[i].backedPool)
                .closePosition(marketId, allocation);
            _markets[marketId].pools[i].totalSize -= allocation;
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
    ) internal returns (uint256[] memory allocations) {
        BackedPoolState[] memory allPools = _markets[marketId].pools;
        allocations = new uint256[](allPools.length);
        allocations[0] = size; // TODO: allocate
    }

    /**
     * @dev split x into [x1, x2, ...] (the same length as .pools)
     *      according to the factor of .pools[i].totalSize
     * @return allocations [amount of .pools[i]]
     */
    function _deallocateLiquidity(
        bytes32 marketId,
        uint256 size
    ) internal returns (uint256[] memory allocations) {
        BackedPoolState[] memory allPools = _markets[marketId].pools;
        allocations = new uint256[](allPools.length);
        allocations[0] = size; // TODO: allocate
    }

    function _updateMarketBorrowingFee(
        bytes32 marketId,
        uint256 marketPrice
    ) internal {
        MarketInfo storage market = _markets[marketId];
        require(market.pools.length > 0);
        // interval
        uint256 interval = _configs.getUint256(MC_BORROWING_INTERVAL);
        uint256 blockTime = block.timestamp;
        if (blockTime - market.lastBorrowingFeeUpdateTime < interval) {
            return;
        }
        uint256 timespan = blockTime - market.lastBorrowingFeeUpdateTime;
        if (timespan == 0) {
            return;
        }
        // unpaid_i += $size * timespan * apy
        // acc += Σ($size * timespan * apy) / Σ($size)
        uint256 totalFeeValue = 0;
        uint256 totalPositionValue = 0;
        for (uint256 i = 0; i < market.pools.length; i++) {
            BackedPoolState storage marketPool = market.pools[i];
            uint256 positionValue = (marketPrice * marketPool.totalSize) / 1e18;
            uint256 feeRateApy = ICollateralPool(marketPool.backedPool)
                .borrowingFeeRateApy();
            uint256 feeValue = (positionValue * feeRateApy) / 1e18;
            feeValue = (feeValue * timespan) / (365 * 86400);
            totalFeeValue += feeValue;
            totalPositionValue += positionValue;
            marketPool.unpaidBorrowingFeeUsd += feeValue;
        }
        if (totalPositionValue > 0) {
            market.cumulatedBorrowingPerUsd +=
                (totalFeeValue * 1e18) /
                totalPositionValue;
        }
        market.lastBorrowingFeeUpdateTime = blockTime;
    }

    function _dispatchBorrowingFee(
        address trader,
        bytes32 marketId,
        bytes32 positionId,
        address[] memory feeAddresses,
        uint256[] memory feeAmounts // [amount foreach backed pools], decimals = 18
    ) internal {
        MarketInfo storage market = _markets[marketId];
        uint256 length = market.pools.length;
        require(length > 0, "no pool");
        // using unpaid fee as distribution
        uint256[] memory allocations = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            allocations[i] = market.pools[i].unpaidBorrowingFeeUsd;
        }
        _dispatchFee(
            trader,
            marketId,
            positionId,
            feeAddresses,
            feeAmounts,
            allocations
        );
        // TODO: do we need to update unpaidBorrowingFeeUsd?
    }

    function _dispatchFee(
        address trader,
        bytes32 marketId,
        bytes32 positionId,
        address[] memory feeAddresses,
        uint256[] memory feeAmounts, // [amount foreach feeAddresses], decimals = 18
        uint256[] memory allocations // [amount foreach backed pools], decimals = 18
    ) internal {
        uint256 length = feeAddresses.length;
        require(
            length == feeAmounts.length,
            "mismatched feeAddresses and feeAmounts"
        );
        require(
            allocations.length == _markets[marketId].pools.length,
            "mismatched allocations and backed pools"
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
}
