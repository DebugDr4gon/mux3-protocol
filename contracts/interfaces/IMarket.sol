// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "../interfaces/IConfigTable.sol";

struct BackedPoolState {
    address backedPool;
    uint256 totalSize;
    uint256 unpaidBorrowingFeeUsd;
}

struct MarketInfo {
    string symbol;
    bool isLong;
    uint256 cumulatedBorrowingPerUsd; // sum of all pools
    uint256 lastBorrowingFeeUpdateTime;
    ConfigTable configs;
    BackedPoolState[] pools;
}

struct AllocationData {
    bytes32 marketId;
    uint256 size;
}

interface IMarket {
    event CollectFee(address feeToken, uint256 wad);
}
