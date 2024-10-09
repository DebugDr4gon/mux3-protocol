// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/ICollateralPool.sol";
import "../libraries/LibConfigTable.sol";
import "../libraries/LibTypeCast.sol";
import "./CollateralPoolStore.sol";

contract CollateralPoolComputed is CollateralPoolStore {
    using LibTypeCast for uint256;
    using LibTypeCast for int256;
    using LibTypeCast for bytes32;
    using LibConfigTable for ConfigTable;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _liqudityFeeRate() internal view returns (uint256) {
        return _configTable.getUint256(MCP_LIQUIDITY_FEE_RATE);
    }

    function _liquidityCapUsd() internal view returns (uint256) {
        return _configTable.getUint256(MCP_LIQUIDITY_CAP_USD);
    }

    function _borrowingBaseApy() internal view returns (int256) {
        return
            IFacetReader(_core).configValue(MC_BORROWING_BASE_APY).toInt256();
    }

    function _borrowingK() internal view returns (int256) {
        return _configTable.getInt256(MCP_BORROWING_K);
    }

    function _borrowingB() internal view returns (int256) {
        return _configTable.getInt256(MCP_BORROWING_B);
    }

    function _feeDistributor() internal view returns (address) {
        return IFacetReader(_core).configValue(MC_FEE_DISTRIBUTOR).toAddress();
    }

    function _adlReserveRate(
        bytes32 marketId
    ) internal view returns (uint256 rate) {
        bytes32 key = keccak256(
            abi.encodePacked(MCP_ADL_RESERVE_RATE, marketId)
        );
        rate = _configTable.getUint256(key);
    }

    function _adlMaxPnlRate(
        bytes32 marketId
    ) internal view returns (uint256 rate) {
        bytes32 key = keccak256(
            abi.encodePacked(MCP_ADL_MAX_PNL_RATE, marketId)
        );
        rate = _configTable.getUint256(key);
    }
    function _adlTriggerRate(
        bytes32 marketId
    ) internal view returns (uint256 rate) {
        bytes32 key = keccak256(
            abi.encodePacked(MCP_ADL_TRIGGER_RATE, marketId)
        );
        rate = _configTable.getUint256(key);
    }

    function _aumUsdWithoutPnl(
        uint256 collateralPrice
    ) internal view returns (uint256 aum) {
        aum = ((_liquidityBalance * collateralPrice) / 1e18);
    }

    function _nav(uint256 liquidityUsd) internal view returns (uint256) {
        uint256 shares = totalSupply();
        if (shares == 0) {
            return 1e18;
        }
        return (liquidityUsd * 1e18) / shares;
    }

    // non-negative aum of pool, borrowing fee excluded
    function _aumUsd(
        uint256 collateralPrice
    ) internal view returns (uint256 aum) {
        int256 upnl;
        uint256 length = _marketIds.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = _marketIds.at(i);
            upnl += _traderTotalUpnlUsd(marketId);
        }
        upnl = _aumUsdWithoutPnl(collateralPrice).toInt256() - upnl;
        aum = upnl > 0 ? uint256(upnl) : 0;
    }

    function _traderTotalUpnlUsd(
        bytes32 marketId
    ) internal view returns (int256 upnlUsd) {
        MarketState storage data = _marketStates[marketId];
        uint256 marketPrice = IFacetReader(_core).priceOf(marketId);
        if (data.isLong) {
            upnlUsd =
                (int256(data.totalSize) *
                    (int256(marketPrice) - int256(data.averageEntryPrice))) /
                1e18;
        } else {
            upnlUsd =
                (int256(data.totalSize) *
                    (int256(data.averageEntryPrice) - int256(marketPrice))) /
                1e18;
        }
    }

    function _reservedUsd() internal view returns (uint256 reservedUsd) {
        uint256 length = _marketIds.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = _marketIds.at(i);
            MarketState storage data = _marketStates[marketId];
            uint256 reserveRatio = _adlReserveRate(marketId);
            require(reserveRatio > 0, "zero reserveRatio");
            uint256 marketPrice = IFacetReader(_core).priceOf(marketId);
            uint256 sizeUsd = (data.totalSize * marketPrice) / 1e18;
            reservedUsd += (sizeUsd * reserveRatio) / 1e18;
        }
    }

    function _availableLiquidityUsd()
        internal
        view
        returns (uint256 liquidityUsd)
    {
        uint256 collateralPrice = IFacetReader(_core).priceOf(
            address(_collateralToken)
        );
        uint256 aum = _aumUsdWithoutPnl(collateralPrice);
        uint256 reserved = _reservedUsd();
        if (aum >= reserved) {
            liquidityUsd = aum - reserved;
        }
    }

    function _toWad(uint256 rawAmount) internal view returns (uint256) {
        if (_collateralDecimals <= 18) {
            return rawAmount * (10 ** (18 - _collateralDecimals));
        } else {
            return rawAmount / (10 ** (_collateralDecimals - 18));
        }
    }

    function _toRaw(uint256 wadAmount) internal view returns (uint256) {
        if (_collateralDecimals <= 18) {
            return wadAmount / 10 ** (18 - _collateralDecimals);
        } else {
            return wadAmount * 10 ** (_collateralDecimals - 18);
        }
    }
}
