// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract SimplePriceProvider {
    function getOraclePrice(
        bytes32,
        bytes memory rawData
    ) external view returns (uint256, uint256) {
        uint256 price = abi.decode(rawData, (uint256));
        return (price, block.timestamp);
    }
}
