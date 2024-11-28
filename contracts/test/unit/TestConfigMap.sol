// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../libraries/LibConfigMap.sol";
import "../TestSuit.sol";

contract TestConfigMap is TestSuit {
    using LibConfigMap for mapping(bytes32 => bytes32);

    mapping(bytes32 => bytes32) table;

    function key(string memory name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    function test_setUint256() external {
        LibConfigMap.setUint256(table, key("TK0"), 0x1234);
        assertEq(LibConfigMap.getUint256(table, key("TK0")), 0x1234, "E01");

        LibConfigMap.setUint256(table, key("TK1"), 0x4321);
        assertEq(LibConfigMap.getUint256(table, key("TK0")), 0x1234, "E02");
        assertEq(LibConfigMap.getUint256(table, key("TK1")), 0x4321, "E03");

        LibConfigMap.setUint256(table, key("TK0"), 0x0);
        assertEq(LibConfigMap.getUint256(table, key("TK0")), 0x0, "E04");

        LibConfigMap.setUint256(table, key("TK1"), 0x0);
        assertEq(LibConfigMap.getUint256(table, key("TK1")), 0x0, "E05");

        LibConfigMap.setBytes32(
            table,
            key("TK0"),
            bytes32(uint256(0x1234000000000000000000000000000000000000000000000000000000000000))
        );
        assertEq(
            LibConfigMap.getBytes32(table, key("TK0")),
            bytes32(uint256(0x1234000000000000000000000000000000000000000000000000000000000000)),
            "E01"
        );

        LibConfigMap.setAddress(table, key("TK0"), address(this));
        assertEq(LibConfigMap.getAddress(table, key("TK0")), address(this), "E06");

        LibConfigMap.setBoolean(table, key("TK0"), true);
        assertEq(LibConfigMap.getBoolean(table, key("TK0")), true, "E08");
        LibConfigMap.setBoolean(table, key("TK0"), false);
        assertEq(LibConfigMap.getBoolean(table, key("TK0")), false, "E09");
    }
}
