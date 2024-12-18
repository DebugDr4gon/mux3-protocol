// SPDX-License-Identifier: GPL-2.0-or-later
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

    function _swapper() internal view returns (address swapper) {
        swapper = _configs.getAddress(MC_SWAPPER);
        require(swapper != address(0), EssentialConfigNotSet("MC_SWAPPER"));
    }

    function _priceOf(address token) internal view virtual returns (uint256 price) {
        price = _priceOf(bytes32(bytes20(token)));
    }

    function _priceOf(bytes32 oracleId) internal view virtual returns (uint256 price) {
        price = uint256(_readCacheUint256(oracleId));
        require(price > 0, MissingPrice(oracleId));
    }

    function _isOracleProvider(address oracleProvider) internal view returns (bool isProvider) {
        isProvider = _oracleProviders[oracleProvider];
    }

    function _isPoolExist(address pool) internal view returns (bool isExist) {
        isExist = _collateralPoolList.contains(pool);
    }

    function _isCollateralExist(address token) internal view returns (bool isExist) {
        isExist = _collateralTokens[token].isExist;
    }

    function _isMarketExist(bytes32 marketId) internal view returns (bool isExist) {
        isExist = _marketList.contains(marketId);
    }

    function _collateralToWad(address collateralToken, uint256 rawAmount) internal view returns (uint256 wadAmount) {
        uint8 decimals = _collateralTokens[collateralToken].decimals;
        if (decimals <= 18) {
            wadAmount = rawAmount * (10 ** (18 - decimals));
        } else {
            wadAmount = rawAmount / (10 ** (decimals - 18));
        }
    }

    function _collateralToRaw(address collateralToken, uint256 wadAmount) internal view returns (uint256 rawAmount) {
        uint8 decimals = _collateralTokens[collateralToken].decimals;
        if (decimals <= 18) {
            rawAmount = wadAmount / 10 ** (18 - decimals);
        } else {
            rawAmount = wadAmount * 10 ** (decimals - 18);
        }
    }

    function _marketPositionFeeRate(bytes32 marketId) internal view returns (uint256 rate) {
        rate = _markets[marketId].configs.getUint256(MM_POSITION_FEE_RATE);
        // 0 is valid
    }

    function _marketLiquidationFeeRate(bytes32 marketId) internal view returns (uint256 rate) {
        rate = _markets[marketId].configs.getUint256(MM_LIQUIDATION_FEE_RATE);
        // 0 is valid
    }

    function _marketInitialMarginRate(bytes32 marketId) internal view returns (uint256 rate) {
        rate = _markets[marketId].configs.getUint256(MM_INITIAL_MARGIN_RATE);
        require(rate > 0, EssentialConfigNotSet("MM_INITIAL_MARGIN_RATE"));
    }

    function _marketOracleId(bytes32 marketId) internal view returns (bytes32 oracleId) {
        oracleId = _markets[marketId].configs.getBytes32(MM_ORACLE_ID);
        require(oracleId != bytes32(0), EssentialConfigNotSet("MM_ORACLE_ID"));
    }

    function _marketOpenInterestCap(bytes32 marketId) internal view returns (uint256 capUsd) {
        capUsd = _markets[marketId].configs.getUint256(MM_OPEN_INTEREST_CAP_USD);
        require(capUsd > 0, EssentialConfigNotSet("MM_OPEN_INTEREST_CAP_USD"));
    }

    function _marketDisableTrade(bytes32 marketId) internal view returns (bool isDisabled) {
        isDisabled = _markets[marketId].configs.getBoolean(MM_DISABLE_TRADE);
    }

    function _marketDisableOpen(bytes32 marketId) internal view returns (bool isDisabled) {
        isDisabled = _markets[marketId].configs.getBoolean(MM_DISABLE_OPEN);
    }

    function _marketMaintenanceMarginRate(bytes32 marketId) internal view returns (uint256 rate) {
        rate = _markets[marketId].configs.getUint256(MM_MAINTENANCE_MARGIN_RATE);
        // 0 is valid
    }

    function _marketLotSize(bytes32 marketId) internal view returns (uint256 lotSize) {
        lotSize = _markets[marketId].configs.getUint256(MM_LOT_SIZE);
        require(lotSize > 0, EssentialConfigNotSet("MM_LOT_SIZE"));
    }

    function _feeDistributor() internal view returns (address feeDistributor) {
        feeDistributor = _configs.getAddress(MC_FEE_DISTRIBUTOR);
        require(feeDistributor != address(0), EssentialConfigNotSet("MC_FEE_DISTRIBUTOR"));
    }

    function _readCacheUint256(bytes32 key) internal view returns (bytes32 value) {
        assembly {
            value := tload(key)
        }
    }

    function _strictStableDeviation() internal view returns (uint256 deviation) {
        deviation = _configs.getUint256(MC_STRICT_STABLE_DEVIATION);
        require(deviation > 0, EssentialConfigNotSet("MC_STRICT_STABLE_DEVIATION"));
    }

    /**
     * @dev Get active collaterals of a trader
     *
     * @param lastConsumedToken optional. try to avoid consuming this token if possible.
     */
    function _activeCollateralsWithLastWithdraw(
        bytes32 positionId,
        address lastConsumedToken
    ) internal view returns (address[] memory collaterals) {
        collaterals = _positionAccounts[positionId].activeCollaterals.values();
        if (lastConsumedToken == address(0)) {
            return collaterals;
        }
        uint256 length = collaterals.length;
        if (length <= 1) {
            return collaterals;
        }
        // swap lastConsumedToken to the end
        for (uint256 i = 0; i < length - 1; i++) {
            if (collaterals[i] == lastConsumedToken) {
                collaterals[i] = collaterals[length - 1];
                collaterals[length - 1] = lastConsumedToken;
                break;
            }
        }
    }
}
