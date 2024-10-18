// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract TestCache {
    uint256 public m;

    function readCacheUint256(bytes32 key) internal view returns (bytes32) {
        bytes32 value;
        assembly {
            value := tload(key)
        }
        return value;
    }

    function writeCacheUint256(bytes32 key, bytes32 n) internal {
        assembly {
            tstore(key, n)
        }
    }

    function do1(uint256 n) external {}

    function do2(uint256 n) external {
        m = n;
        m = 0;
    }

    function do3(uint256 n) external {
        writeCacheUint256(keccak256("123"), bytes32(n));
        // uint256(readCacheUint256(keccak256("123")));
    }
}
