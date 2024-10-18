// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../interfaces/IPriceProvider.sol";

import "../Mux3FacetBase.sol";

contract Pricing is Mux3FacetBase {
    function _setPrice(
        bytes32 priceId,
        address provider,
        bytes memory oracleCallData
    ) internal returns (uint256 price, uint256 timestamp) {
        require(priceId != bytes32(0), InvalidId(priceId));
        require(provider != address(0), InvalidAddress(provider));
        (price, timestamp) = IPriceProvider(provider).getOraclePrice(
            priceId,
            oracleCallData
        );
        _setCachedPrice(priceId, price);
    }

    function _setCachedPrice(bytes32 priceId, uint256 price) internal {
        _writeCacheUint256(priceId, price);
    }

    function _writeCacheUint256(bytes32 key, uint256 n) internal {
        assembly {
            tstore(key, n)
        }
    }
}
