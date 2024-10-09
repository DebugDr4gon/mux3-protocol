// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

library LibCodec {
    function encodePrice(
        uint8 oracleIndex,
        uint8 exp,
        uint32 mantissa
    ) internal pure returns (uint32) {
        // |---- 7 ----|- 5 -|- 20 -|
        // | oracle id | exp | mant |
        require(mantissa & 0xfff00000 == 0, "mantissa overflow");
        return (uint32(oracleIndex) << 25) | (uint32(exp) << 20) | mantissa;
    }

    function decodePrice(
        uint32 raw
    ) internal pure returns (uint8 oracleIndex, uint256 wad) {
        // |---- 7 ----|- 5 -|- 20 -|
        // | oracle id | exp | mant |
        oracleIndex = uint8(raw >> 25);
        wad = uint256(raw & 0xfffff) * (10 ** uint256((raw >> 20) & 0x1f));
    }

    /**
     * @dev convert [
     *        0x<price1><price2>...<price8>,
     *        0x<price9><price10>...<price16>
     *      ] into [
     *         <price1>, <price2>, ... <price16>
     *      ]
     *      please ignore oracleIndex == 0 outside this function
     */
    function decodePriceBlocks(
        uint256[] memory priceBlocks
    )
        internal
        pure
        returns (uint8[] memory oracleIndexes, uint256[] memory wads)
    {
        oracleIndexes = new uint8[](priceBlocks.length * 8);
        wads = new uint256[](priceBlocks.length * 8);
        uint256 pos = 0;
        for (uint256 i = 0; i < priceBlocks.length; i++) {
            uint256 rawBlock = priceBlocks[i];
            for (uint256 j = 0; j < 8; j++) {
                uint32 raw = uint32(rawBlock >> 224);
                (oracleIndexes[pos], wads[pos]) = decodePrice(raw);
                rawBlock = rawBlock << 32;
                pos++;
            }
        }
    }

    function decodePositionId(
        bytes32 positionId
    ) internal pure returns (address trader, uint256 positionIndex) {
        //  |----- 160 -----|------ 8 -------|-- 88 --|
        //  | user address  | position index | unused |
        trader = address(bytes20(positionId));
        positionIndex = uint256(uint8(uint256(positionId) >> 88));
    }

    function encodePositionId(
        address trader,
        uint256 positionIndex
    ) internal pure returns (bytes32) {
        return bytes32(bytes20(trader)) | bytes32(positionIndex << 88);
    }
}
