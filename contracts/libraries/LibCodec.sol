// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

library LibCodec {
    function decodePositionId(
        bytes32 positionId
    ) internal pure returns (address trader, uint96 positionIndex) {
        //  |----- 160 -----|------ 96 ------|
        //  | user address  | position index |
        trader = address(bytes20(positionId));
        positionIndex = uint96(uint256(positionId));
    }

    function encodePositionId(
        address trader,
        uint96 positionIndex
    ) internal pure returns (bytes32) {
        return bytes32(bytes20(trader)) | bytes32(uint256(positionIndex));
    }
}
