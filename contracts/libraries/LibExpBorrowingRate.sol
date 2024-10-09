// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import "../interfaces/IBorrowingRate.sol";
import "../libraries/LibLogExp.sol";

library LibExpBorrowingRate {
    function validatePoolConfig(
        IBorrowingRate.Global memory global,
        IBorrowingRate.Pool memory pool
    ) internal pure {
        require(pool.k != 0, "ExpBorrow: k = 0");
        int256 fr = pool.k + pool.b;
        fr = LibLogExp.exp(fr);
        fr = global.baseApy + fr;
        require(fr >= 0, "ExpBorrow: negative fr");
        require(fr < 10e18, "ExpBorrow: fr too large"); // apy 1000%
    }

    /**
     * @dev get pool borrowing rate
     *
     *      fr = globalBase + E^(k * util + b)
     *      util = reservedUsd / poolSizeUsd
     */
    function getBorrowingRate2(
        IBorrowingRate.Global memory conf,
        IBorrowingRate.Pool memory pool
    ) internal pure returns (int256 fr) {
        int256 util = 0;
        if (pool.poolSizeUsd > 0) {
            util = (pool.reservedUsd * 1e18) / pool.poolSizeUsd;
        }
        fr = (pool.k * util) / 1e18 + pool.b;
        fr = LibLogExp.exp(fr);
        fr = conf.baseApy + fr;
        return fr;
    }

    struct PoolState {
        IBorrowingRate.Pool conf;
        int256 k; // k := pool.k / pool.aum
        int256 b; // b := pool.k * pool.reserve / pool.aum + pool.b
        int256 maxX;
        int256 allocated;
    }

    function initPoolState(
        IBorrowingRate.Pool memory conf
    ) internal pure returns (PoolState memory state) {
        state.conf = conf;
        state.k = (conf.k * 1e18) / conf.poolSizeUsd;
        state.maxX = conf.poolSizeUsd - conf.reservedUsd;
        recalculateB(state);
    }

    function recalculateB(PoolState memory state) internal pure {
        // b := k * (reservedUsd + allocated) / aum + b
        state.b =
            ((state.conf.reservedUsd + state.allocated) * state.conf.k) /
            state.conf.poolSizeUsd +
            state.conf.b;
    }

    function allocate(PoolState memory state, int256 xi) internal pure {
        require(xi <= state.maxX, "ExpBorrow: xi too large");
        state.allocated += xi;
        state.maxX -= xi;
        recalculateB(state);
    }

    function deallocate(PoolState memory state, int256 xi) internal pure {
        require(xi <= state.allocated, "ExpBorrow: xi too large");
        state.allocated -= xi;
        state.maxX += xi;
        recalculateB(state);
    }

    function isMaxCapacityReached(
        PoolState memory state
    ) internal pure returns (bool) {
        return
            state.conf.reservedUsd + state.allocated >= state.conf.poolSizeUsd;
    }

    /**
     * @dev sort pools[0:n] by b
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

    function calculateC(
        AllocateMem memory mem,
        int256 poolsN,
        int256 xTotal
    ) internal pure returns (int256 c) {
        // c = (xTotal + Σ(b/k)) / Σ(1/k)
        int256 i = poolsN - 1;
        mem.cacheBk +=
            (mem.pools[uint256(i)].b * 1e18) /
            mem.pools[uint256(i)].k;
        mem.cache1k += 1e36 / mem.pools[uint256(i)].k;
        c = ((xTotal + mem.cacheBk) * 1e18) / mem.cache1k;
    }

    function calculateXi(
        AllocateMem memory mem,
        int256 i,
        int256 c
    ) internal pure returns (int256 xi) {
        // x1 = (c - b1) / k1
        xi = ((c - mem.pools[uint256(i)].b) * 1e18) / mem.pools[uint256(i)].k;
    }

    /**
     * @dev one round of allocation
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

    struct AllocateResult {
        address poolId;
        int256 xi;
    }

    /**
     * @dev allocate x to pools
     */
    function allocate2(
        IBorrowingRate.Pool[] memory pools,
        int256 xTotal
    ) internal pure returns (AllocateResult[] memory result) {
        AllocateMem memory mem;
        mem.pools = new PoolState[](pools.length);
        mem.xTotal = xTotal;
        mem.poolCount = int256(pools.length);
        mem.poolsN = int256(pools.length);
        mem.bestXi = new int256[](pools.length);
        mem.candidate = new int256[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            mem.pools[i] = initPoolState(pools[i]);
        }
        return allocate3(mem);
    }

    function allocate3(
        AllocateMem memory mem
    ) internal pure returns (AllocateResult[] memory result) {
        // in each iteration, move full pools to the end
        bool poolUpdated = true; // some pools are moved
        while (
            mem.totalAllocated < mem.xTotal && mem.poolsN > 0 && poolUpdated
        ) {
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
                        mem.pools[uint256(i)] = mem.pools[
                            uint256(mem.poolsN - 1)
                        ];
                        mem.pools[uint256(mem.poolsN - 1)] = tmp;
                    }
                    mem.poolsN--;
                    poolUpdated = true;
                }
            }
        }

        // if allocated > xTotal, reduce the xi from the last
        for (int256 i = mem.poolCount - 1; i >= 0; i--) {
            if (mem.totalAllocated <= mem.xTotal) {
                break;
            }
            int256 deduct = mem.totalAllocated - mem.xTotal;
            if (deduct > mem.pools[uint256(i)].allocated) {
                deduct = mem.pools[uint256(i)].allocated;
            }
            if (deduct < 0) {
                deduct = 0;
            }
            deallocate(mem.pools[uint256(i)], deduct);
            mem.totalAllocated -= deduct;
        }

        // if allocated > xTotal, increase from the first
        for (int256 i = 0; i < mem.poolCount; i++) {
            if (mem.xTotal <= mem.totalAllocated) {
                break;
            }
            int256 add = mem.xTotal - mem.totalAllocated;
            if (add > mem.pools[uint256(i)].maxX) {
                add = mem.pools[uint256(i)].maxX;
            }
            allocate(mem.pools[uint256(i)], add);
            mem.totalAllocated += add;
        }

        // still mismatched, means all pools are full
        require(mem.totalAllocated == mem.xTotal, "ExpBorrow: full");

        // return result
        result = new AllocateResult[](uint256(mem.poolCount));
        for (int256 i = 0; i < mem.poolCount; i++) {
            PoolState memory pool = mem.pools[uint256(i)];
            result[uint256(i)] = AllocateResult(
                pool.conf.poolId,
                pool.allocated
            );
        }
    }
}
