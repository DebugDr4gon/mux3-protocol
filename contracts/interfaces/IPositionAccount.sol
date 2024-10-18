// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

uint256 constant UNSAFE_INITITAL = 0x1;
uint256 constant UNSAFE_MAINTENANCE = 0x2;
uint256 constant UNSAFE_LEVERAGE = 0x3;

struct PositionAccountInfo {
    address owner;
    EnumerableSetUpgradeable.AddressSet activeCollaterals;
    EnumerableSetUpgradeable.Bytes32Set activeMarkets;
    mapping(address => uint256) collaterals; // decimals = 18
    mapping(bytes32 => PositionData) positions; // marketId (implied isLong) => PositionData
}

struct PositionData {
    uint256 initialLeverage;
    uint256 lastIncreasedTime;
    uint256 realizedBorrowingUsd; // TODO: not implmented yet
    mapping(address => PositionPoolData) pools; // poolId => PositionPoolData
}

struct PositionPoolData {
    uint256 size;
    uint256 entryPrice;
    uint256 entryBorrowing;
}
