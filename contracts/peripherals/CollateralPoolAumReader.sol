// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

import "../interfaces/IMux3Core.sol";
import "../interfaces/ICollateralPool.sol";
import "../libraries/LibTypeCast.sol";

contract CollateralPoolAumReader is Initializable, OwnableUpgradeable {
    using LibTypeCast for uint256;
    using LibTypeCast for bytes32;

    uint256 public constant PRICE_EXPIRATION = 86400; // 1 day

    uint256 public priceExpiration;
    mapping(bytes32 => address) public marketPriceProviders;
    mapping(address => address) public tokenPriceProviders;

    event SetTokenPriceProvider(address token, address oracleProvider);
    event SetMarketPriceProvider(bytes32 marketId, address oracleProvider);
    event SetPriceExpiration(uint256 priceExpiration);

    function initialize() public initializer {
        __Ownable_init();

        priceExpiration = PRICE_EXPIRATION;
    }

    function setMarketPriceProvider(bytes32 marketId, address oracleProvider) public onlyOwner {
        require(oracleProvider != address(0), "InvalidAddress");
        marketPriceProviders[marketId] = oracleProvider;
        emit SetMarketPriceProvider(marketId, oracleProvider);
    }

    function setTokenPriceProvider(address token, address oracleProvider) public onlyOwner {
        require(oracleProvider != address(0), "InvalidAddress");
        tokenPriceProviders[token] = oracleProvider;
        emit SetTokenPriceProvider(token, oracleProvider);
    }

    function setPriceExpiration(uint256 _priceExpiration) public onlyOwner {
        priceExpiration = _priceExpiration;
        emit SetPriceExpiration(_priceExpiration);
    }

    /**
     * @notice An AUM that can be used on chain. it uses on-chain prices and should be similar to
     *         CollateralPool._aumUsd() which is used in addLiquidity/removeLiquidity.
     *
     *         this function is not used inner MUX3 contracts. other contacts can use this value to
     *         estimate the value of LP token.
     */
    function estimatedAumUsd(address pool) public view returns (uint256 aum) {
        // get all market ids
        (bytes32[] memory marketIds, MarketState[] memory states) = ICollateralPool(pool).marketStates();
        int256 upnl;
        uint256 length = marketIds.length;
        for (uint256 i = 0; i < length; i++) {
            upnl += _traderTotalUpnlUsd(pool, marketIds[i], states[i]);
        }
        upnl = _aumUsdWithoutPnl(pool).toInt256() - upnl;
        aum = upnl > 0 ? uint256(upnl) : 0;
    }

    function getTokenPrice(address token) external view returns (uint256 price, uint256 timestamp) {
        address provider = tokenPriceProviders[token];
        require(provider != address(0), "OracleProviderNotSet");
        return _getOraclePrice(provider);
    }

    function getMarketPrice(bytes32 marketId) external view returns (uint256 price, uint256 timestamp) {
        address provider = marketPriceProviders[marketId];
        require(provider != address(0), "OracleProviderNotSet");
        return _getOraclePrice(provider);
    }

    function _priceOf(bytes32 marketId) internal view returns (uint256 price) {
        address oracleProvider = marketPriceProviders[marketId];
        require(oracleProvider != address(0), "OracleProviderNotSet");
        (price, ) = _getOraclePrice(oracleProvider);
    }

    function _priceOf(address token) internal view returns (uint256 price) {
        address oracleProvider = tokenPriceProviders[token];
        require(oracleProvider != address(0), "OracleProviderNotSet");
        (price, ) = _getOraclePrice(oracleProvider);
    }

    function _traderTotalUpnlUsd(
        address pool,
        bytes32 marketId,
        MarketState memory data
    ) internal view returns (int256 upnlUsd) {
        uint256 marketPrice = _priceOf(marketId);
        // upnl of all traders as a whole
        if (data.isLong) {
            upnlUsd = (int256(data.totalSize) * (int256(marketPrice) - int256(data.averageEntryPrice))) / 1e18;
        } else {
            upnlUsd = (int256(data.totalSize) * (int256(data.averageEntryPrice) - int256(marketPrice))) / 1e18;
        }
        // trader upnl is affected by adl parameters
        if (upnlUsd > 0) {
            uint256 maxPnlRate = _adlMaxPnlRate(pool, marketId);
            uint256 maxPnlUsd = (data.totalSize * data.averageEntryPrice) / 1e18;
            maxPnlUsd = (maxPnlUsd * maxPnlRate) / 1e18;
            upnlUsd = MathUpgradeable.min(uint256(upnlUsd), maxPnlUsd).toInt256();
        }
    }

    function _adlMaxPnlRate(address pool, bytes32 marketId) internal view returns (uint256 rate) {
        bytes32 key = keccak256(abi.encodePacked(MCP_ADL_MAX_PNL_RATE, marketId));
        rate = ICollateralPool(pool).configValue(key).toUint256();
        require(rate > 0, "AdlMaxPnlRateNotSet");
    }

    function _aumUsdWithoutPnl(address pool) internal view returns (uint256 aum) {
        (address[] memory tokens, uint256[] memory balances) = ICollateralPool(pool).liquidityBalances();
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = balances[i];
            if (balance == 0) {
                continue;
            }
            uint256 price = _priceOf(token);
            aum += (balance * price) / 1e18;
        }
    }

    function _getOraclePrice(address feeder) internal view returns (uint256 price, uint256 timestamp) {
        AggregatorV2V3Interface aggregator = AggregatorV2V3Interface(feeder);
        uint8 decimals = aggregator.decimals();
        int256 rawPrice;
        (, rawPrice, , timestamp, ) = aggregator.latestRoundData();
        require(rawPrice > 0, "InvalidPrice");
        require(timestamp + priceExpiration >= block.timestamp, "PriceExpired");
        if (decimals <= 18) {
            price = uint256(rawPrice) * (10 ** (18 - decimals));
        } else {
            price = uint256(rawPrice) / (10 ** (decimals - 18));
        }
    }
}
