// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

library IBorrowingRate {
    struct Global {
        int256 baseApy;
    }

    struct Pool {
        uint256 poolId; // the allocator does not care what is a poolId, you can use any index or address here
        int256 k;
        int256 b;
        bool highPriority; // always allocate from this pool if true
        int256 poolSizeUsd;
        int256 reservedUsd;
        int256 reserveRate;
    }

    struct AllocateResult {
        uint256 poolId; // the allocator does not care what is a poolId, you can use any index or address here
        int256 xi; // result of allocation
    }
}
