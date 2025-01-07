// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../interfaces/ICollateralPool.sol";
import "../interfaces/IErrors.sol";
import "../libraries/LibConfigMap.sol";
import "../libraries/LibTypeCast.sol";
import "./CollateralPoolStore.sol";

contract CollateralPoolComputed is CollateralPoolStore {
    using LibTypeCast for uint256;
    using LibTypeCast for int256;
    using LibTypeCast for bytes32;
    using LibConfigMap for mapping(bytes32 => bytes32);
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _liquidityFeeRate() internal view returns (uint256 rate) {
        rate = _configTable.getUint256(MCP_LIQUIDITY_FEE_RATE);
        // 0 is valid
    }

    function _liquidityCapUsd() internal view returns (uint256 capUsd) {
        capUsd = _configTable.getUint256(MCP_LIQUIDITY_CAP_USD);
        // 0 is valid
    }

    function _borrowingBaseApy() internal view returns (int256 baseApy) {
        baseApy = IFacetReader(_core).configValue(MC_BORROWING_BASE_APY).toInt256();
        // 0 is valid
    }

    function _borrowingK() internal view returns (int256 k) {
        k = _configTable.getInt256(MCP_BORROWING_K);
        require(k != 0, IErrors.EssentialConfigNotSet("MCP_BORROWING_K"));
    }

    function _borrowingB() internal view returns (int256 b) {
        b = _configTable.getInt256(MCP_BORROWING_B);
        // 0 is valid
    }

    function _feeDistributor() internal view returns (address feeDistributor) {
        feeDistributor = IFacetReader(_core).configValue(MC_FEE_DISTRIBUTOR).toAddress();
        require(feeDistributor != address(0), IErrors.EssentialConfigNotSet("MC_FEE_DISTRIBUTOR"));
    }

    function _marketOracleId(bytes32 marketId) internal view returns (bytes32 oracleId) {
        oracleId = IFacetReader(_core).marketConfigValue(marketId, MM_ORACLE_ID);
        require(oracleId != bytes32(0), IErrors.EssentialConfigNotSet("MM_ORACLE_ID"));
    }

    function _isCollateralExist(address token) internal view returns (bool isExist) {
        (isExist, , ) = IFacetReader(_core).getCollateralToken(token);
    }

    function _adlReserveRate(bytes32 marketId) internal view returns (uint256 rate) {
        bytes32 key = keccak256(abi.encodePacked(MCP_ADL_RESERVE_RATE, marketId));
        rate = _configTable.getUint256(key);
        require(rate > 0, IErrors.EssentialConfigNotSet("MCP_ADL_RESERVE_RATE"));
    }

    function _adlMaxPnlRate(bytes32 marketId) internal view returns (uint256 rate) {
        bytes32 key = keccak256(abi.encodePacked(MCP_ADL_MAX_PNL_RATE, marketId));
        rate = _configTable.getUint256(key);
        require(rate > 0, IErrors.EssentialConfigNotSet("MCP_ADL_MAX_PNL_RATE"));
    }

    function _adlTriggerRate(bytes32 marketId) internal view returns (uint256 rate) {
        bytes32 key = keccak256(abi.encodePacked(MCP_ADL_TRIGGER_RATE, marketId));
        rate = _configTable.getUint256(key);
        require(rate > 0, IErrors.EssentialConfigNotSet("MCP_ADL_TRIGGER_RATE"));
    }

    function _isDraining() internal view returns (bool isDraining) {
        isDraining = _configTable.getBoolean(MCP_IS_DRAINING);
        // false is valid
    }

    /**
     * @dev _collateralTokenUsd represents the value of pool.collateralToken. this is used to reserve for potential PnL.
     */
    function _collateralTokenUsd() internal view returns (uint256 collateralUsd) {
        address token = _collateralToken;
        uint256 balance = _liquidityBalances[token];
        if (balance == 0) {
            return 0;
        }
        uint256 price = IFacetReader(_core).priceOf(token);
        collateralUsd = (balance * price) / 1e18;
    }

    /**
     * @dev AUM without unrealized PnL
     */
    function _aumUsdWithoutPnl() internal view returns (uint256 aum) {
        address[] memory tokens = IFacetReader(_core).listCollateralTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = _liquidityBalances[token];
            if (balance == 0) {
                continue;
            }
            uint256 price = IFacetReader(_core).priceOf(token);
            aum += (balance * price) / 1e18;
        }
    }

    /**
     * @dev NAV = AUM / shares. Used for addLiquidity and removeLiquidity
     */
    function _nav(uint256 liquidityUsd) internal view returns (uint256) {
        uint256 shares = totalSupply();
        if (shares == 0) {
            return 1e18;
        }
        return (liquidityUsd * 1e18) / shares;
    }

    /**
     * @dev AUM including unrealized PnL. this is used to evaluate NAV
     *      note: never negative
     *      note: borrowing fee excluded
     */
    function _aumUsd() internal view returns (uint256 aum) {
        int256 upnl;
        uint256 length = _marketIds.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = _marketIds.at(i);
            upnl += _traderTotalUpnlUsd(marketId);
        }
        upnl = _aumUsdWithoutPnl().toInt256() - upnl;
        aum = upnl > 0 ? uint256(upnl) : 0;
    }

    function _traderTotalUpnlUsd(bytes32 marketId) internal view returns (int256 upnlUsd) {
        MarketState storage data = _marketStates[marketId];
        uint256 marketPrice = IFacetReader(_core).priceOf(_marketOracleId(marketId));
        // upnl of all traders as a whole
        if (data.isLong) {
            upnlUsd = (int256(data.totalSize) * (int256(marketPrice) - int256(data.averageEntryPrice))) / 1e18;
        } else {
            upnlUsd = (int256(data.totalSize) * (int256(data.averageEntryPrice) - int256(marketPrice))) / 1e18;
        }
        // trader upnl is affected by adl parameters
        if (upnlUsd > 0) {
            uint256 maxPnlRate = _adlMaxPnlRate(marketId);
            uint256 maxPnlUsd = (data.totalSize * data.averageEntryPrice) / 1e18;
            maxPnlUsd = (maxPnlUsd * maxPnlRate) / 1e18;
            upnlUsd = MathUpgradeable.min(uint256(upnlUsd), maxPnlUsd).toInt256();
        }
    }

    /**
     * @dev reservedUsd represents the maximum collaterals that collateralPool reserves for potential position profits.
     *      * When collateralPool uses stablecoin (e.g., long/short ETH with USDC as collateral),
     *        reserved = entryPrice * size * reserveRatio
     *      * When collateralPool uses non-stablecoin (e.g., long ETH with ETH as collateral),
     *        reserved = marketPrice * size * reserveRatio,
     *        note that both numerator and denominator of util contain marketPrice.
     */
    function _reservedUsd() internal view returns (uint256 reservedUsd) {
        (, , bool isStable) = IFacetReader(_core).getCollateralToken(_collateralToken);
        uint256 length = _marketIds.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = _marketIds.at(i);
            MarketState storage data = _marketStates[marketId];
            uint256 reserveRatio = _adlReserveRate(marketId);
            if (isStable) {
                uint256 sizeUsd = (data.totalSize * data.averageEntryPrice) / 1e18;
                reservedUsd += (sizeUsd * reserveRatio) / 1e18;
            } else {
                uint256 marketPrice = IFacetReader(_core).priceOf(_marketOracleId(marketId));
                uint256 sizeUsd = (data.totalSize * marketPrice) / 1e18;
                reservedUsd += (sizeUsd * reserveRatio) / 1e18;
            }
        }
    }

    function _toWad(address token, uint256 rawAmount) internal view returns (uint256) {
        (bool isExist, uint8 decimals, ) = IFacetReader(_core).getCollateralToken(token);
        require(isExist, IErrors.CollateralNotExist(token));
        if (decimals <= 18) {
            return rawAmount * (10 ** (18 - decimals));
        } else {
            return rawAmount / (10 ** (decimals - 18));
        }
    }

    function _toRaw(address token, uint256 wadAmount) internal view returns (uint256) {
        (bool isExist, uint8 decimals, ) = IFacetReader(_core).getCollateralToken(token);
        require(isExist, IErrors.CollateralNotExist(token));
        if (decimals <= 18) {
            return wadAmount / 10 ** (18 - decimals);
        } else {
            return wadAmount * 10 ** (decimals - 18);
        }
    }
}
