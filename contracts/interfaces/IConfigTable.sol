// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

struct ConfigTable {
    bytes32[] keys;
    mapping(bytes32 => bytes32) values;
}
