// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../Mux3FacetBase.sol";

contract PricingManager is Mux3FacetBase {
    function _setOracleProvider(address oracleProvider, bool isValid) internal {
        require(oracleProvider != address(0), InvalidAddress(oracleProvider));
        _oracleProviders[oracleProvider] = isValid;
    }
}
