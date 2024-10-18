// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

struct BackedPoolState {
    address backedPool;
}

struct MarketInfo {
    string symbol;
    bool isLong;
    mapping(bytes32 => bytes32) configs;
    BackedPoolState[] pools;
}

struct AllocationData {
    bytes32 marketId;
    uint256 size;
}

interface IMarket {
    event CollectFee(address feeToken, uint256 wad);
}
