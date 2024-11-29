// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "../Mux3FacetBase.sol";

contract CollateralManager is Mux3FacetBase {
    using LibConfigMap for mapping(bytes32 => bytes32);
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _addCollateralToken(address token, uint8 decimals) internal {
        require(token != address(0), InvalidAddress(token));
        require(!_isCollateralExist(token), CollateralAlreadyExist(token));
        _collateralTokens[token] = CollateralTokenInfo({ isExist: true, decimals: _retrieveDecimals(token, decimals) });
        require(
            _collateralTokenList.length < MAX_COLLATERAL_TOKENS,
            CapacityExceeded(MAX_COLLATERAL_TOKENS, _collateralTokenList.length, 1)
        );
        _collateralTokenList.push(token);
    }

    function _setStrictStableId(bytes32 oracleId, bool strictStable) internal {
        _strictStableIds[oracleId] = strictStable;
    }

    function _retrieveDecimals(address token, uint8 defaultDecimals) internal view returns (uint8) {
        try IERC20MetadataUpgradeable(token).decimals() returns (uint8 tokenDecimals) {
            require(tokenDecimals == defaultDecimals, UnmatchedDecimals(tokenDecimals, defaultDecimals));
            return tokenDecimals;
        } catch {
            return defaultDecimals;
        }
    }
}
