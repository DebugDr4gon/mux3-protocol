// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import "../../interfaces/IFacetManagement.sol";
import "../Mux3FacetBase.sol";
import "./PoolManager.sol";
import "./MarketManager.sol";
import "./CollateralManager.sol";
import "./PricingManager.sol";

contract FacetManagement is
    Mux3FacetBase,
    Mux3RolesAdmin,
    PoolManager,
    MarketManager,
    CollateralManager,
    PricingManager,
    IFacetManagement,
    IBeacon
{
    using LibConfigMap for mapping(bytes32 => bytes32);

    function initialize(address weth_) external initializer {
        __LibMux3Roles_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _weth = weth_;
    }

    function implementation() public view virtual override returns (address) {
        return _collateralPoolImplementation;
    }

    function setCollateralPoolImplementation(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setImplementation(newImplementation);
        emit SetCollateralPoolImplementation(newImplementation);
    }

    function addCollateralToken(address token, uint8 decimals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addCollateralToken(token, decimals);
        emit AddCollateralToken(token, decimals);
    }

    function setStrictStableId(bytes32 oracleId, bool strictStable) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setStrictStableId(oracleId, strictStable);
        emit SetStrictStableId(oracleId, strictStable);
    }

    function setOracleProvider(address oracleProvider, bool isValid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setOracleProvider(oracleProvider, isValid);
        emit SetOracleProvider(oracleProvider, isValid);
    }

    function createCollateralPool(
        string memory name,
        string memory symbol,
        address collateralToken,
        uint256 oldPoolCount // expected pools count before creating. this is to prevent from submitting tx twice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
        require(_isCollateralExist(collateralToken), CollateralNotExist(collateralToken));
        address pool = _createCollateralPool(name, symbol, collateralToken, oldPoolCount);
        emit CreateCollateralPool(name, symbol, collateralToken, _collateralTokens[collateralToken].decimals, pool);
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

    function setConfig(bytes32 key, bytes32 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _configs.setBytes32(key, value);
        emit SetConfig(key, value);
    }

    function setMarketConfig(bytes32 marketId, bytes32 key, bytes32 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMarketConfig(marketId, key, value);
        emit SetMarketConfig(marketId, key, value);
    }

    function setPoolConfig(address pool, bytes32 key, bytes32 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPoolConfigs(pool, key, value);
        emit SetCollateralPoolConfig(pool, key, value);
    }

    function setPrice(
        bytes32 oracleId,
        address provider,
        bytes memory oracleCalldata
    ) external virtual onlyRole(ORDER_BOOK_ROLE) {
        (uint256 price, uint256 timestamp) = _setPrice(oracleId, provider, oracleCalldata);
        emit SetPrice(oracleId, provider, oracleCalldata, price, timestamp);
    }
}
