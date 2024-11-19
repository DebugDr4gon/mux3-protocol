// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

library LibCodec {
    // |----- 160 -----|------ 96 ------|
    // | user address  | position index |
    //
    // note:
    // * positionIndex == 0: the PositionAccount can have multiple collaterals and multiple market positions
    // * positionIndex != 0: the PositionAccount can have multiple collaterals but only single market position
    function decodePositionId(bytes32 positionId) internal pure returns (address trader, uint96 positionIndex) {
        trader = address(bytes20(positionId));
        positionIndex = uint96(uint256(positionId));
    }

    function encodePositionId(address trader, uint96 positionIndex) internal pure returns (bytes32) {
        return bytes32(bytes20(trader)) | bytes32(uint256(positionIndex));
    }
}
