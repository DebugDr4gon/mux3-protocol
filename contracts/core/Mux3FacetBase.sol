// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "../interfaces/IConstants.sol";
import "./Mux3Store.sol";
import "./Mux3Computed.sol";

contract Mux3FacetBase is Mux3Store, Mux3Computed, IErrors {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _isPoolExist(address pool) internal view returns (bool) {
        return _collateralPoolList.contains(pool);
    }

    function _isOracleProvider(
        address oracleProvider
    ) internal view returns (bool) {
        return _oracleProviders[oracleProvider];
    }

    function _isAuthorized(
        address caller,
        bytes32 positionId
    ) internal pure returns (bool) {
        // TODO: access controll
        (address owner, ) = LibCodec.decodePositionId(positionId);
        return caller == owner;
    }

    function _isCollateralEnabled(address token) internal view returns (bool) {
        return _collateralTokens[token].enabled == Enabled.Enabled;
    }

    function _isCollateralExists(address token) internal view returns (bool) {
        return _collateralTokens[token].enabled != Enabled.Invalid;
    }

    function _isMarketExists(bytes32 marketId) internal view returns (bool) {
        return _marketList.contains(marketId);
    }

    function _collateralToWad(
        address collateralToken,
        uint256 rawAmount
    ) internal view returns (uint256) {
        uint8 decimals = _collateralTokens[collateralToken].decimals;
        if (decimals <= 18) {
            return rawAmount * (10 ** (18 - decimals));
        } else {
            return rawAmount / (10 ** (decimals - 18));
        }
    }

    function _collateralToRaw(
        address collateralToken,
        uint256 wadAmount
    ) internal view returns (uint256) {
        uint8 decimals = _collateralTokens[collateralToken].decimals;
        if (decimals <= 18) {
            return wadAmount / 10 ** (18 - decimals);
        } else {
            return wadAmount * 10 ** (decimals - 18);
        }
    }
}
