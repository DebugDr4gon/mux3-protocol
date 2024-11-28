// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "./LibTypeCast.sol";

library LibConfigMap {
    using LibTypeCast for bytes32;
    using LibTypeCast for address;
    using LibTypeCast for uint256;
    using LibTypeCast for bool;

    event SetValue(bytes32 key, bytes32 value);

    // ================================== single functions ======================================

    function setUint256(mapping(bytes32 => bytes32) storage store, bytes32 key, uint256 value) internal {
        setBytes32(store, key, bytes32(value));
    }

    function setAddress(mapping(bytes32 => bytes32) storage store, bytes32 key, address value) internal {
        setBytes32(store, key, bytes32(bytes20(value)));
    }

    function setBytes32(mapping(bytes32 => bytes32) storage store, bytes32 key, bytes32 value) internal {
        store[key] = value;
        emit SetValue(key, value);
    }

    function setBoolean(mapping(bytes32 => bytes32) storage store, bytes32 key, bool flag) internal {
        bytes32 value = bytes32(uint256(flag ? 1 : 0));
        setBytes32(store, key, value);
    }

    function getBytes32(mapping(bytes32 => bytes32) storage store, bytes32 key) internal view returns (bytes32) {
        return store[key];
    }

    function getUint256(mapping(bytes32 => bytes32) storage store, bytes32 key) internal view returns (uint256) {
        return store[key].toUint256();
    }

    function getInt256(mapping(bytes32 => bytes32) storage store, bytes32 key) internal view returns (int256) {
        return store[key].toInt256();
    }

    function getAddress(mapping(bytes32 => bytes32) storage store, bytes32 key) internal view returns (address) {
        return store[key].toAddress();
    }

    function getBoolean(mapping(bytes32 => bytes32) storage store, bytes32 key) internal view returns (bool) {
        return store[key].toBoolean();
    }

    function toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(bytes20(a));
    }
}
