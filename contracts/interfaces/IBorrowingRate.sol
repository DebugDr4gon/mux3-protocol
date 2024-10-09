// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

library IBorrowingRate {
    struct Global {
        int256 baseApy;
    }

    struct Pool {
        address poolId;
        int256 k;
        int256 b;
        bool highPriority;
        int256 poolSizeUsd;
        int256 reservedUsd;
    }
}
