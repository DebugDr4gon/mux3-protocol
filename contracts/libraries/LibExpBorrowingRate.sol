// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../interfaces/IBorrowingRate.sol";
import "../interfaces/IErrors.sol";
import "../libraries/LibLogExp.sol";
import "../libraries/LibTypeCast.sol";

library LibExpBorrowingRate {
    using LibTypeCast for uint256;
    using LibTypeCast for int256;

    /**
     * @dev Get pool borrowing rate
     *
     *      fr = globalBase + E^(k * util + b)
     *      util = reservedUsd / poolSizeUsd
     */
    function getBorrowingRate2(
        IBorrowingRate.Global memory conf,
        IBorrowingRate.AllocatePool memory pool
    ) internal pure returns (int256 fr) {
        if (pool.poolSizeUsd > 0) {
            fr = (pool.reservedUsd * pool.k) / pool.poolSizeUsd;
        } else {
            // let util = 0, thus k * util = 0
        }
        fr = fr + pool.b;
        fr = LibLogExp.exp(fr);
        fr = conf.baseApy + fr;
        return fr;
    }

    /**
     * @dev Round an allocation result to lotSize, so that the sum of allocations = target
     *
     *      note: the returned allocations may slightly exceed pool capacity (because of rounding),
     *            we consider this is acceptable.
     */
    function alignAllocationToLotSize(
        uint256 target,
        uint256[] memory allocations,
        uint256 lotSize
    ) internal pure returns (uint256[] memory results) {
        results = new uint256[](allocations.length);
        require(lotSize > 0, IErrors.EssentialConfigNotSet("MM_LOT_SIZE"));

        // round down all allocations and keep track of the largest fractional part
        uint256 sumAligned = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            results[i] = (allocations[i] / lotSize) * lotSize;
            sumAligned += results[i];
        }
        if (sumAligned == target) {
            return results;
        }
        if (sumAligned > target) {
            // this implies that sum(allocations) > target. we leave this case to the caller
            return results;
        }
        // distribute the remainder. O(n^2)
        uint256 remainder = target - sumAligned;
        uint256 lotsToDistribute = remainder / lotSize; // should near allocations.length
        require(
            lotsToDistribute < allocations.length * 100, // loop protection
            IErrors.CapacityExceeded(allocations.length * 100, 0, lotsToDistribute)
        );
        for (uint256 remain = 0; remain < lotsToDistribute; remain++) {
            // find the largest remainder
            uint256 maxDiffIndex = 0;
            int256 maxDiff = -1;
            for (uint256 i = 0; i < allocations.length; i++) {
                int256 diff = allocations[i].toInt256() - results[i].toInt256();
                if (diff > maxDiff) {
                    maxDiff = diff;
                    maxDiffIndex = i;
                }
            }
            results[maxDiffIndex] += lotSize;
        }
    }

    struct PoolState {
        IBorrowingRate.AllocatePool conf;
        int256 k; // k := pool.k * pool.reserveRate / pool.aum
        int256 b; // b := pool.k * pool.reserved    / pool.aum + pool.b
        int256 maxX; // (aum - reserved) / reserveRate
        int256 allocated;
    }

    function initPoolState(IBorrowingRate.AllocatePool memory conf) internal pure returns (PoolState memory state) {
        require(conf.k > 0, IErrors.EssentialConfigNotSet("MCP_BORROWING_K"));
        require(conf.poolSizeUsd > 0, IErrors.InvalidAmount("poolSizeUsd")); // pools with no liquidity should be excluded
        require(conf.reserveRate > 0, IErrors.EssentialConfigNotSet("MCP_ADL_RESERVE_RATE"));
        state.conf = conf;
        state.k = (conf.k * conf.reserveRate) / conf.poolSizeUsd;
        // roundUp the maxX, so that isMaxCapacityReached can be detected easily
        if (conf.poolSizeUsd > conf.reservedUsd) {
            state.maxX = _maxPossibleXToFillPool(conf.poolSizeUsd, conf.reservedUsd, conf.reserveRate);
        } else {
            state.maxX = 0;
        }
        recalculateB(state);
    }

    function _maxPossibleXToFillPool(
        int256 poolSizeUsd,
        int256 reservedUsd,
        int256 reserveRate
    ) private pure returns (int256) {
        return Math.ceilDiv((poolSizeUsd - reservedUsd).toUint256() * 1e18, reserveRate.toUint256()).toInt256();
    }

    function recalculateB(PoolState memory state) internal pure {
        // b := k * (reservedUsd + allocated * reserveRate) / aum + b
        int256 ret = (state.allocated * state.conf.reserveRate) / 1e18;
        ret += state.conf.reservedUsd;
        ret = (ret * state.conf.k) / state.conf.poolSizeUsd;
        ret += state.conf.b;
        state.b = ret;
    }

    function allocate(PoolState memory state, int256 xi) internal pure {
        require(xi <= state.maxX, IErrors.BadAllocation(state.maxX, xi));
        state.allocated += xi;
        state.maxX -= xi;
        recalculateB(state);
    }

    function deallocate(PoolState memory state, int256 xi) internal pure {
        require(xi <= state.allocated, IErrors.BadAllocation(state.allocated, xi));
        state.allocated -= xi;
        state.maxX += xi;
        recalculateB(state);
    }

    function isMaxCapacityReached(PoolState memory state) internal pure returns (bool) {
        int256 ret = (state.allocated * state.conf.reserveRate) / 1e18;
        ret += state.conf.reservedUsd;
        return ret >= state.conf.poolSizeUsd;
    }

    /**
     * @dev Sort pools[0:n] by b
     *
     *      we assume len(pools) < 10, a quicksort is even worse than insertion sort
     */
    function sort(PoolState[] memory pools, int256 n) internal pure {
        for (int256 i = 1; i < n; i++) {
            PoolState memory key = pools[uint256(i)];
            int256 j = i - 1;
            while (j >= 0 && pools[uint256(j)].b > key.b) {
                pools[uint256(j + 1)] = pools[uint256(j)];
                j--;
            }
            pools[uint256(j + 1)] = key;
        }
    }

    // note: xTotal is usd
    struct AllocateMem {
        // input
        int256 poolCount;
        int256 xTotal;
        // pools[:poolsN] are allocating pools.
        // pools[poolsN:] are full pools.
        // note that the order of pools[] is changing after sort().
        PoolState[] pools;
        int256 poolsN;
        int256 totalAllocated;
        int256[] bestXi;
        int256[] candidate;
        // cache partial sum for:
        //  c = (xTotal + Σ(b/k)) / Σ(1/k)
        //  x1 = (c - b1) / k1
        int256 cacheBk;
        int256 cache1k;
    }

    function calculateC(AllocateMem memory mem, int256 poolsN, int256 xTotal) internal pure returns (int256 c) {
        // c = (xTotal + Σ(b/k)) / Σ(1/k)
        int256 i = poolsN - 1;
        mem.cacheBk += (mem.pools[uint256(i)].b * 1e18) / mem.pools[uint256(i)].k;
        mem.cache1k += 1e36 / mem.pools[uint256(i)].k;
        c = ((xTotal + mem.cacheBk) * 1e18) / mem.cache1k;
    }

    function calculateXi(AllocateMem memory mem, int256 i, int256 c) internal pure returns (int256 xi) {
        // x1 = (c - b1) / k1
        xi = ((c - mem.pools[uint256(i)].b) * 1e18) / mem.pools[uint256(i)].k;
    }

    /**
     * @dev One round of allocation
     *
     *      in each round, try 1 pool, 2 pools, 3 pools, ... until xi[i] < 0,
     *      save the xi of min cost into mem.bestXi
     */
    function oneRound(AllocateMem memory mem, int256 xTotal) internal pure {
        // clear all
        mem.cacheBk = 0;
        mem.cache1k = 0;
        int256 bestCost = type(int256).max;
        for (int256 i = 0; i < mem.poolsN; i++) {
            mem.bestXi[uint256(i)] = 0;
        }

        // enum poolsN until xi[i] < 0
        for (int256 n = 1; n <= mem.poolsN; n++) {
            int256 c = calculateC(mem, n, xTotal);
            if (c >= bestCost) {
                continue;
            }

            // skip if xi[i] < 0, because this is an approximate algorithm
            for (int256 i = 0; i < n; i++) {
                mem.candidate[uint256(i)] = 0;
            }
            for (int256 i = 0; i < n; i++) {
                mem.candidate[uint256(i)] = calculateXi(mem, i, c);
                if (mem.candidate[uint256(i)] < 0) {
                    break;
                }

                // prevent overflow
                if (mem.candidate[uint256(i)] > mem.pools[uint256(i)].maxX) {
                    mem.candidate[uint256(i)] = mem.pools[uint256(i)].maxX;
                }
            }

            // save
            bestCost = c;
            for (int256 i = 0; i < n; i++) {
                mem.bestXi[uint256(i)] = mem.candidate[uint256(i)];
            }
        }
    }

    /**
     * @dev This is the entry point for allocate xTotalUsd into all pools,
     *      considering borrowing rate equalization, and liquidity capacity.
     *
     *      note:
     *      1. `xTotalUsd` and `pools[].poolSizeUsd` should be USD.
     *      2. the returned allocation may slightly exceed pool capacity (because of rounding). this is acceptable.
     *      3. you can apply alignAllocationToLotSize outside this function if needed.
     */
    function allocate2(
        IBorrowingRate.AllocatePool[] memory pools, // only pools[:poolLength] are valid
        uint256 poolLength,
        int256 xTotalUsd
    ) internal pure returns (IBorrowingRate.AllocateResult[] memory result) {
        require(poolLength > 0, IErrors.MarketFull());
        // init
        AllocateMem memory mem;
        mem.pools = new PoolState[](poolLength);
        mem.xTotal = xTotalUsd;
        mem.poolCount = int256(poolLength);
        mem.poolsN = int256(poolLength);
        mem.bestXi = new int256[](poolLength);
        mem.candidate = new int256[](poolLength);
        for (uint256 i = 0; i < poolLength; i++) {
            mem.pools[i] = initPoolState(pools[i]);
        }
        result = new IBorrowingRate.AllocateResult[](poolLength);
        // in each iteration, move full pools to the end
        bool poolUpdated = true; // some pools are moved
        while (mem.totalAllocated < mem.xTotal && mem.poolsN > 0 && poolUpdated) {
            sort(mem.pools, mem.poolsN);
            oneRound(mem, mem.xTotal - mem.totalAllocated);

            // move full pools to the end. in order to prevent index
            // problem, iterate backwards
            poolUpdated = false;
            for (int256 i = mem.poolsN - 1; i >= 0; i--) {
                int256 x = mem.bestXi[uint256(i)];
                allocate(mem.pools[uint256(i)], x);
                mem.totalAllocated += x;
                if (isMaxCapacityReached(mem.pools[uint256(i)])) {
                    // remove the element by swap it with the last element
                    if (i != mem.poolsN - 1) {
                        PoolState memory tmp = mem.pools[uint256(i)];
                        mem.pools[uint256(i)] = mem.pools[uint256(mem.poolsN - 1)];
                        mem.pools[uint256(mem.poolsN - 1)] = tmp;
                    }
                    mem.poolsN--;
                    poolUpdated = true;
                }
            }
        }

        // all pools are full
        // this is an approximation algorithm, so allocated == xTotal almost never happens.
        // here we only check the case where pools are likely full: allocated < xTotal && all pools are full.
        // remains the following cases:
        // 1. pools are full but current allocation is fine
        // 2. allocated is slightly less than xTotal and pools are not full (this case will be covered in Market.sol)
        if (mem.totalAllocated < mem.xTotal) {
            bool isAllFull = true;
            for (int256 i = 0; i < mem.poolsN; i++) {
                if (!isMaxCapacityReached(mem.pools[uint256(i)])) {
                    isAllFull = false;
                    break;
                }
            }
            require(!isAllFull, IErrors.MarketFull());
        }

        // return result
        for (int256 i = 0; i < mem.poolCount; i++) {
            PoolState memory pool = mem.pools[uint256(i)];
            result[uint256(i)] = IBorrowingRate.AllocateResult(pool.conf.poolId, pool.allocated);
        }
    }

    /**
     * @dev This is the entry point for deallocate xTotal from all pools.
     *
     *      note:
     *      1. `xTotal` is NOT necessarily USD. we do not care about the unit.
     *      2. you can apply alignAllocationToLotSize outside this function if needed.
     */
    function deallocate2(
        IBorrowingRate.DeallocatePool[] memory confs,
        int256 xTotal
    ) internal pure returns (IBorrowingRate.DeallocateResult[] memory result) {
        result = new IBorrowingRate.DeallocateResult[](confs.length);
        int256 totalSizeInPools = 0;
        for (uint256 i = 0; i < confs.length; i++) {
            totalSizeInPools += confs[i].mySizeForPool;
        }
        require(xTotal <= totalSizeInPools, IErrors.BadAllocation(totalSizeInPools, xTotal));
        for (uint256 i = 0; i < confs.length; i++) {
            int256 xi = 0;
            if (totalSizeInPools > 0) {
                xi = (xTotal * confs[i].mySizeForPool) / totalSizeInPools;
            }
            result[i] = IBorrowingRate.DeallocateResult(confs[i].poolId, xi);
        }
    }
}
