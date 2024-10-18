// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../libraries/LibCodec.sol";

contract TestCodec {
    function encodePrice(uint8 oracleIndex, uint8 exp, uint32 price) external pure returns (uint32) {
        return LibCodec.encodePrice(oracleIndex, exp, price);
    }

    function decodePrice(uint32 raw) external pure returns (uint8 oracleIndex, uint256 wad) {
        return LibCodec.decodePrice(raw);
    }

    function decodePriceBlocks(
        uint256[] memory priceBlocks
    ) external pure returns (uint8[] memory indexes, uint256[] memory prices) {
        return LibCodec.decodePriceBlocks(priceBlocks);
    }

    function decodePositionId(bytes32 positionId) external pure returns (address, uint256) {
        return LibCodec.decodePositionId(positionId);
    }

    function encodePositionId(address account, uint256 index) external pure returns (bytes32) {
        return LibCodec.encodePositionId(account, index);
    }
}
