// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import "../../interfaces/IManagement.sol";
import "../../interfaces/IConstants.sol";

import "../Mux3FacetBase.sol";
import "./PoolManager.sol";
import "./MarketManager.sol";
import "./CollateralManager.sol";
import "./PricingManager.sol";

contract FacetManagement is
    Mux3FacetBase,
    PoolManager,
    MarketManager,
    CollateralManager,
    PricingManager,
    IManagement,
    IBeacon
{
    using LibConfigMap for mapping(bytes32 => bytes32);

    function implementation() public view virtual override returns (address) {
        return _collateralPoolImplementation;
    }

    function setCollateralPoolImplementation(
        address newImplementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setImplementation(newImplementation);
        emit SetCollateralPoolImplementation(newImplementation);
    }

    function addCollateralToken(
        address token,
        uint8 decimals
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addCollateralToken(token, decimals);
        emit AddCollateralToken(token, decimals);
    }

    function setCollateralTokenStatus(
        address token,
        bool enabled
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setCollateralTokenEnabled(token, enabled);
        emit SetCollateralTokenEnabled(token, enabled);
    }

    function setOracleProvider(
        address oracleProvider,
        bool isValid
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setOracleProvider(oracleProvider, isValid);
        emit SetOracleProvider(oracleProvider, isValid);
    }

    function createCollateralPool(
        string memory name,
        string memory symbol,
        address collateralToken,
        uint8 collateralDecimals
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
        require(
            _isCollateralExists(collateralToken),
            CollateralNotExists(collateralToken)
        );
        address pool = _createCollateralPool(
            name,
            symbol,
            collateralToken,
            collateralDecimals
        );
        emit CreateCollateralPool(
            name,
            symbol,
            collateralToken,
            collateralDecimals,
            pool
        );
        return pool;
    }

    function createMarket(
        bytes32 marketId,
        string memory symbol,
        bool isLong,
        address[] memory backedPools
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _createMarket(marketId, symbol, isLong);
        emit CreateMarket(marketId, symbol, isLong, backedPools);
        _appendBackedPoolsToMarket(marketId, backedPools);
        emit AppendBackedPoolsToMarket(marketId, backedPools);
    }

    function appendBackedPoolsToMarket(
        bytes32 marketId,
        address[] memory backedPools
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _appendBackedPoolsToMarket(marketId, backedPools);
        emit AppendBackedPoolsToMarket(marketId, backedPools);
    }

    function setConfig(
        bytes32 key,
        bytes32 value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _configs.setBytes32(key, value);
        emit SetConfig(key, value);
    }

    function setMarketConfig(
        bytes32 marketId,
        bytes32 key,
        bytes32 value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMarketConfig(marketId, key, value);
        emit SetMarketConfig(marketId, key, value);
    }

    function setPoolConfig(
        address pool,
        bytes32 key,
        bytes32 value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPoolConfigs(pool, key, value);
        emit SetCollateralPoolConfig(pool, key, value);
    }
}
