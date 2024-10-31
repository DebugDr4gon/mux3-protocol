// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract TestSuit {
    error Exception(string id);
    error ExceptionInt256(string id, int256 actual, int256 expect);
    error ExceptionUint256(string id, uint256 actual, uint256 expect);
    error ExceptionAddress(string id, address actual, address expect);
    error ExceptionBytes32(string id, bytes32 actual, bytes32 expect);
    error ExceptionBoolean(string id, bool actual, bool expect);

    function assertEq(uint256 actual, uint256 expect, string memory errorId) public pure {
        require(actual == expect, ExceptionUint256(errorId, actual, expect));
    }

    function assertEq(address actual, address expect, string memory errorId) public pure {
        require(actual == expect, ExceptionAddress(errorId, actual, expect));
    }

    function assertEq(bytes32 actual, bytes32 expect, string memory errorId) public pure {
        require(actual == expect, ExceptionBytes32(errorId, actual, expect));
    }

    function assertEq(bool actual, bool expect, string memory errorId) public pure {
        require(actual == expect, ExceptionBoolean(errorId, actual, expect));
    }

    function assertEq(int256 actual, int256 expect, string memory errorId) public pure {
        require(actual == expect, ExceptionInt256(errorId, actual, expect));
    }

    function makeArray(address addr0) public pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr0;
        return arr;
    }

    function makeArray(address addr0, address addr1) public pure returns (address[] memory) {
        address[] memory arr = new address[](2);
        arr[0] = addr0;
        arr[1] = addr1;
        return arr;
    }

    function makeArray(address addr0, address addr1, address addr2) public pure returns (address[] memory) {
        address[] memory arr = new address[](3);
        arr[0] = addr0;
        arr[1] = addr1;
        arr[2] = addr2;
        return arr;
    }

    function makeArray(uint256 num0) public pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = num0;
        return arr;
    }

    function makeArray(uint256 num0, uint256 num1) public pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](2);
        arr[0] = num0;
        arr[1] = num1;
        return arr;
    }

    function makeArray(uint256 num0, uint256 num1, uint256 num2) public pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](3);
        arr[0] = num0;
        arr[1] = num1;
        arr[2] = num2;
        return arr;
    }
}
