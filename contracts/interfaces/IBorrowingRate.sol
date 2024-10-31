// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

library IBorrowingRate {
    struct Global {
        int256 baseApy;
    }

    struct AllocatePool {
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
        int256 xi; // result of allocation. unit is usd
    }

    struct DeallocatePool {
        uint256 poolId; // the deallocator does not care what is a poolId, you can use any index or address here
        bool highPriority;
        int256 mySizeForPool; // not necessarily usd. we even do not care about the unit of "mySizeForPool"
    }

    struct DeallocateResult {
        uint256 poolId; // the allocator does not care what is a poolId, you can use any index or address here
        int256 xi; // not necessarily usd. we even do not care about the unit of "mySizeForPool"
    }
}
