// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "../Mux3FacetBase.sol";

contract PricingManager is Mux3FacetBase {
    function _setOracleProvider(address oracleProvider, bool isValid) internal {
        require(oracleProvider != address(0), InvalidAddress(oracleProvider));
        _oracleProviders[oracleProvider] = isValid;
    }
}
