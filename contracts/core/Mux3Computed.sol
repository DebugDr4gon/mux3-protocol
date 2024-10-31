// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../interfaces/IConstants.sol";
import "../libraries/LibConfigMap.sol";
import "../libraries/LibTypeCast.sol";
import "./Mux3Store.sol";

contract Mux3Computed is Mux3Store, IErrors {
    using LibTypeCast for int256;
    using LibTypeCast for uint256;
    using LibConfigMap for mapping(bytes32 => bytes32);
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _priceOf(address token) internal view virtual returns (uint256) {
        return _priceOf(bytes32(bytes20(token)));
    }

    function _priceOf(
        bytes32 oracleId
    ) internal view virtual returns (uint256) {
        uint256 price = uint256(_readCacheUint256(oracleId));
        require(price > 0, MissingPrice(oracleId));
        return price;
    }

    function _isPoolExist(address pool) internal view returns (bool) {
        return _collateralPoolList.contains(pool);
    }

    function _isOracleProvider(
        address oracleProvider
    ) internal view returns (bool) {
        return _oracleProviders[oracleProvider];
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
    function _marketPositionFeeRate(
        bytes32 marketId
    ) internal view returns (uint256) {
        return _markets[marketId].configs.getUint256(MM_POSITION_FEE_RATE);
    }

    function _marketLiquidationFeeRate(
        bytes32 marketId
    ) internal view returns (uint256) {
        return _markets[marketId].configs.getUint256(MM_LIQUIDATION_FEE_RATE);
    }

    function _marketInitialMarginRate(
        bytes32 marketId
    ) internal view returns (uint256) {
        return _markets[marketId].configs.getUint256(MM_INITIAL_MARGIN_RATE);
    }

    function _marketOracleId(bytes32 marketId) internal view returns (bytes32) {
        return _markets[marketId].configs.getBytes32(MM_ORACLE_ID);
    }

    function _marketMaintenanceMarginRate(
        bytes32 marketId
    ) internal view returns (uint256) {
        return
            _markets[marketId].configs.getUint256(MM_MAINTENANCE_MARGIN_RATE);
    }

    function _marketLotSize(bytes32 marketId) internal view returns (uint256) {
        return _markets[marketId].configs.getUint256(MM_LOT_SIZE);
    }

    function _feeDistributor() internal view returns (address) {
        return _configs.getAddress(MC_FEE_DISTRIBUTOR);
    }

    function _readCacheUint256(bytes32 key) internal view returns (bytes32) {
        bytes32 value;
        assembly {
            value := tload(key)
        }
        return value;
    }

    /**
     * @dev get activating collaterals of a trader. lastWithdrawToken will be moved to
     *      the last item in the returned array so that it can be used as the last withdraw token.
     */
    function _activeCollateralsWithLastWithdraw(
        bytes32 positionId,
        address lastWithdrawToken
    ) internal view returns (address[] memory collaterals) {
        collaterals = _positionAccounts[positionId].activeCollaterals.values();
        if (lastWithdrawToken == address(0)) {
            return collaterals;
        }
        // swap lastWithdrawCollateral to the end
        uint256 length = collaterals.length;
        for (uint256 i = 0; i < length - 1; i++) {
            if (collaterals[i] == lastWithdrawToken) {
                collaterals[i] = collaterals[length - 1];
                collaterals[length - 1] = lastWithdrawToken;
                break;
            }
        }
    }
}
