// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../interfaces/IPriceProvider.sol";
import "../Mux3FacetBase.sol";

contract PricingManager is Mux3FacetBase {
    using LibTypeCast for bytes32;
    uint256 constant STABLE_TOKEN_PRICE = 1e18;

    function _setPrice(
        bytes32 oracleId,
        address provider,
        bytes memory oracleCallData
    ) internal returns (uint256 price, uint256 timestamp) {
        require(oracleId != bytes32(0), InvalidId("oracleId"));
        require(provider != address(0), InvalidAddress(provider));
        (price, timestamp) = IPriceProvider(provider).getOraclePrice(oracleId, oracleCallData);
        if (_strictStableIds[oracleId]) {
            uint256 deviation = _strictStableDeviation();
            uint256 tolerance = (STABLE_TOKEN_PRICE * deviation) / 1e18;
            if (STABLE_TOKEN_PRICE + tolerance >= price && price >= STABLE_TOKEN_PRICE - tolerance) {
                price = STABLE_TOKEN_PRICE;
            }
        }
        _setCachedPrice(oracleId, price);
    }

    function _setCachedPrice(bytes32 oracleId, uint256 price) internal {
        _writeCacheUint256(oracleId, price);
    }

    function _writeCacheUint256(bytes32 key, uint256 n) internal {
        assembly {
            tstore(key, n)
        }
    }

    function _setOracleProvider(address oracleProvider, bool isValid) internal {
        require(oracleProvider != address(0), InvalidAddress(oracleProvider));
        _oracleProviders[oracleProvider] = isValid;
    }
}
