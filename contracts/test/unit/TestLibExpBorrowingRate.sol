// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../../interfaces/IBorrowingRate.sol";
import { LibExpBorrowingRate } from "../../libraries/LibExpBorrowingRate.sol";

contract TestLibExpBorrowingRate {
    function getBorrowingRates(
        IBorrowingRate.Global memory conf,
        IBorrowingRate.AllocatePool[] memory pools
    ) public pure returns (int256[] memory fr) {
        fr = new int256[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            fr[i] = LibExpBorrowingRate.getBorrowingRate2(conf, pools[i]);
        }
    }

    function testDivRoundUp(uint256 a, uint256 b) public pure returns (uint256) {
        return Math.ceilDiv(a * 1e18, b);
    }

    function testAlignAllocationToLotSize(
        uint256 target,
        uint256[] memory allocations,
        uint256 lotSize
    ) external pure returns (uint256[] memory result) {
        return LibExpBorrowingRate.alignAllocationToLotSize(target, allocations, lotSize);
    }

    function testDistributeEquation(
        IBorrowingRate.AllocatePool[] memory pools,
        int256 xTotalUsd
    ) public pure returns (int256[] memory xi) {
        LibExpBorrowingRate.AllocateMem memory mem;
        mem.poolsN = int256(pools.length);
        mem.pools = new LibExpBorrowingRate.PoolState[](uint256(mem.poolsN));
        for (int256 i = 0; i < mem.poolsN; i++) {
            mem.pools[uint256(i)] = LibExpBorrowingRate.initPoolState(pools[uint256(i)]);
        }
        xi = new int256[](uint256(mem.poolsN));

        int256 c;
        for (int256 i = 1; i <= mem.poolsN; i++) {
            c = LibExpBorrowingRate.calculateC(mem, i, xTotalUsd);
        }
        for (int256 i = 0; i < mem.poolsN; i++) {
            xi[uint256(i)] = LibExpBorrowingRate.calculateXi(mem, i, c);
        }
    }

    function sort(
        LibExpBorrowingRate.PoolState[] memory pools,
        int256 n
    ) external pure returns (LibExpBorrowingRate.PoolState[] memory) {
        LibExpBorrowingRate.sort(pools, n);
        return pools;
    }

    function allocate(
        IBorrowingRate.AllocatePool[] memory pools,
        int256 xTotalUsd
    ) external pure returns (IBorrowingRate.AllocateResult[] memory result) {
        return LibExpBorrowingRate.allocate2(pools, pools.length, xTotalUsd);
    }
}
