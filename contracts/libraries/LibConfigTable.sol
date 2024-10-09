// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "../interfaces/IConfigTable.sol";
import "./LibTypeCast.sol";

library LibConfigTable {
    using LibTypeCast for bytes32;
    using LibTypeCast for address;
    using LibTypeCast for uint256;
    using LibTypeCast for bool;

    event SetValue(bytes32 key, bytes32 value);
    error InvalidAddress(bytes32 key);

    // ================================== single functions ======================================
    function items(
        ConfigTable storage store
    ) internal view returns (bytes32[] memory keys, bytes32[] memory values) {
        uint256 count = store.keys.length;
        keys = new bytes32[](count);
        values = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            keys[i] = store.keys[i];
            values[i] = store.values[keys[i]];
        }
    }

    function setUint256(
        ConfigTable storage store,
        bytes32 key,
        uint256 value
    ) internal {
        setBytes32(store, key, bytes32(value));
    }

    function setBytes32(
        ConfigTable storage store,
        bytes32 key,
        bytes32 value
    ) internal {
        store.values[key] = value;
        emit SetValue(key, value);
    }

    function getBytes32(
        ConfigTable storage store,
        bytes32 key
    ) internal view returns (bytes32) {
        return store.values[key];
    }

    function getUint256(
        ConfigTable storage store,
        bytes32 key
    ) internal view returns (uint256) {
        return store.values[key].toUint256();
    }

    function getInt256(
        ConfigTable storage store,
        bytes32 key
    ) internal view returns (int256) {
        return store.values[key].toInt256();
    }

    function getAddress(
        ConfigTable storage store,
        bytes32 key
    ) internal view returns (address) {
        return store.values[key].toAddress();
    }

    function mustGetAddress(
        ConfigTable storage store,
        bytes32 key
    ) internal view returns (address) {
        address a = getAddress(store, key);
        if (a == address(0)) {
            revert InvalidAddress(key);
        }
        return a;
    }

    function getBoolean(
        ConfigTable storage store,
        bytes32 key
    ) internal view returns (bool) {
        return store.values[key].toBoolean();
    }

    function toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(bytes20(a));
    }
}
