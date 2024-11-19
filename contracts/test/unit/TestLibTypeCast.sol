// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../libraries/LibTypeCast.sol";
import "../TestSuit.sol";

contract TestLibTypeCast is TestSuit {
    function setup() external {}

    function test_typeCast() public pure {
        {
            bytes32 a = 0x1234000000000000000000000000000000004321000000000000000000000000;
            address b = 0x1234000000000000000000000000000000004321;
            assertEq(LibTypeCast.toAddress(a), b, "1");
        }
        {
            address a = 0x1234000000000000000000000000000000004321;
            bytes32 b = 0x1234000000000000000000000000000000004321000000000000000000000000;
            assertEq(LibTypeCast.toBytes32(a), b, "2");
        }
        {
            bytes32 a = 0x1234000000000000000000000000000000004321000000000000000000000000;
            uint256 b = 8233507321867270975858166353462000283756076320976357152479326443076394680320;
            assertEq(LibTypeCast.toUint256(a), b, "3");
        }
        {
            uint256 a = 8233507321867270975858166353462000283756076320976357152479326443076394680320;
            bytes32 b = 0x1234000000000000000000000000000000004321000000000000000000000000;
            assertEq(LibTypeCast.toBytes32(a), b, "4");
        }
        {
            bytes32 a = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc14;
            int256 b = -1004;
            assertEq(LibTypeCast.toInt256(a), b, "5");
        }
        {
            int256 a = -1004;
            bytes32 b = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc14;
            assertEq(LibTypeCast.toBytes32(a), b, "6");
        }
        {
            bytes32 a = 0x0000000000000000000000000000000000000000000000000000000000000001;
            bool b = true;
            assertEq(LibTypeCast.toBoolean(a), b, "7");
        }
        {
            bytes32 a = 0x0000000000000000000000000000000000000000000000000000000000000000;
            bool b = false;
            assertEq(LibTypeCast.toBoolean(a), b, "9");
        }
    }

    function test_typeCast_uintUnderFlow() public pure {
        LibTypeCast.toUint256(-1004);
    }

    function test_typeCast_invalidBoolean() public pure {
        LibTypeCast.toBoolean(0x0000000000000000000000000000000000000000000000000000000000000002);
    }

    function test_typeCast_uint64Overflow() public pure {
        LibTypeCast.toUint64(uint256(type(uint64).max) + 1);
    }

    function test_typeCast_uint96Overflow() public pure {
        LibTypeCast.toUint96(uint256(type(uint96).max) + 1);
    }

    function test_typeCast_int256Overflow() public pure {
        LibTypeCast.toInt256(uint256(type(int256).max) + 1);
    }
}
