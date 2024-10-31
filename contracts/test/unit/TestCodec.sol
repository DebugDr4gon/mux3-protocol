// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../libraries/LibCodec.sol";

contract TestCodec {
    function decodePositionId(bytes32 positionId) external pure returns (address, uint96) {
        return LibCodec.decodePositionId(positionId);
    }

    function encodePositionId(address account, uint96 index) external pure returns (bytes32) {
        return LibCodec.encodePositionId(account, index);
    }
}
