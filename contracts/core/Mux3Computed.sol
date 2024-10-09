// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../libraries/LibConfigTable.sol";
import "../interfaces/IBorrowingRate.sol";
import "../libraries/LibExpBorrowingRate.sol";
import "../libraries/LibTypeCast.sol";
import "../libraries/LibCodec.sol";

import "./Mux3Store.sol";

contract Mux3Computed is Mux3Store {
    using LibTypeCast for int256;
    using LibTypeCast for uint256;
    using LibConfigTable for ConfigTable;

    function _priceOf(address token) internal view virtual returns (uint256) {
        return _priceOf(bytes32(bytes20(token)));
    }

    function _priceOf(bytes32 id) internal view virtual returns (uint256) {
        uint256 price = uint256(_readCacheUint256(id));
        require(price > 0, "price is zero");
        return price;
    }

    function _marketPositionFeeRate(
        bytes32 marketId
    ) internal view returns (uint256) {
        return _markets[marketId].configs.getUint256(MM_POSITION_FEE_RATE);
    }

    function _marketInitialMarginRate(
        bytes32 marketId
    ) internal view returns (uint256) {
        return _markets[marketId].configs.getUint256(MM_INITIAL_MARGIN_RATE);
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

    function _marketCumulativeBorrowingPerUsd(
        bytes32 marketId
    ) internal view returns (uint256) {
        return _markets[marketId].cumulatedBorrowingPerUsd;
    }

    function _marketMaxInitialLeverage(
        bytes32 marketId
    ) internal view returns (uint256) {
        return _markets[marketId].configs.getUint256(MM_MAX_INITIAL_LEVERAGE);
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
}
