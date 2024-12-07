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

    /**
     * @notice Initializes the contract with WETH address
     * @param weth_ The address of the WETH contract
     * @dev Can only be called once due to initializer modifier
     */
    function initialize(address weth_) external initializer {
        __Mux3RolesAdmin_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        require(weth_ != address(0), InvalidAddress(weth_));
        _weth = weth_;
    }

    /**
     * @notice Returns the implementation address for collateral pools (for beacon proxies)
     * @return The address of the current collateral pool implementation
     */
    function implementation() public view virtual override returns (address) {
        return _collateralPoolImplementation;
    }

    /**
     * @notice Sets a new implementation address for collateral pools (for beacon proxies)
     * @param newImplementation The address of the new implementation contract
     * @dev Only callable by admin role
     */
    function setCollateralPoolImplementation(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setImplementation(newImplementation);
        emit SetCollateralPoolImplementation(newImplementation);
    }

    /**
     * @notice Adds a new collateral token to the system
     * @param token The address of the collateral token
     * @param decimals The number of decimals for the token.
     *                 The provided decimals will be verified if the token contract has `decimals()` method.
     * @dev Token cannot be duplicated and cannot be removed
     */
    function addCollateralToken(address token, uint8 decimals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addCollateralToken(token, decimals);
        emit AddCollateralToken(token, decimals);
    }

    /**
     * @notice Sets whether an oracle ID represents a strict stable asset
     * @param oracleId The ID of the oracle
     * @param strictStable Boolean indicating if the asset is a strict stable
     * @dev A token set to be strict stable indicates that mux will treat the price within the ±dampener as $1.abi
     *      eg: assume the dampener is 0.001, a strict stable price within range of [0.999, 1.001] will be treated as 1.000
     */
    function setStrictStableId(bytes32 oracleId, bool strictStable) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setStrictStableId(oracleId, strictStable);
        emit SetStrictStableId(oracleId, strictStable);
    }

    /**
     * @notice Sets the oracle provider whitelist
     * @param oracleProvider The address of the oracle provider
     * @param isValid Boolean indicating if the provider is valid
     * @dev An oracle provider provides validation and normalization of the price from external sources
     */
    function setOracleProvider(address oracleProvider, bool isValid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setOracleProvider(oracleProvider, isValid);
        emit SetOracleProvider(oracleProvider, isValid);
    }

    /**
     * @notice Creates a new collateral pool, duplicated (name, symbol, collateralToken) are not allowed.
     * @param name The name of the pool token
     * @param symbol The symbol of the pool token
     * @param collateralToken The address of the collateral token
     * @param expectedPoolCount the expected number of pools before creating. this is to prevent from submitting tx twice.
     *                         this number is also the expected index of pools array.
     * @return poolAddress The address of the newly created pool
     */
    function createCollateralPool(
        string memory name,
        string memory symbol,
        address collateralToken,
        uint256 expectedPoolCount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address poolAddress) {
        require(_isCollateralExist(collateralToken), CollateralNotExist(collateralToken));
        poolAddress = _createCollateralPool(name, symbol, collateralToken, expectedPoolCount);
        emit CreateCollateralPool(
            name,
            symbol,
            collateralToken,
            _collateralTokens[collateralToken].decimals,
            poolAddress
        );
    }

    /**
     * @notice Creates a new market with specified backed pools, duplicated (marketId) are not allowed.
     * @param marketId The unique identifier for the market
     * @param symbol The symbol for the market
     * @param isLong Whether this is a long market
     * @param backedPools Array of pool addresses that back this market
     * @dev Note that the backed pools can be added later but cannot be removed
     */
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

    /**
     * @notice Adds additional backed pools to an existing market
     * @param marketId The ID of the market to modify
     * @param backedPools Array of pool addresses to add
     */
    function appendBackedPoolsToMarket(
        bytes32 marketId,
        address[] memory backedPools
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _appendBackedPoolsToMarket(marketId, backedPools);
        emit AppendBackedPoolsToMarket(marketId, backedPools);
    }

    /**
     * @notice Sets a global configuration value
     * @param key The configuration key
     * @param value The configuration value
     */
    function setConfig(bytes32 key, bytes32 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _configs.setBytes32(key, value);
        emit SetConfig(key, value);
    }

    /**
     * @notice Sets a market-specific configuration value
     * @param marketId The ID of the market
     * @param key The configuration key
     * @param value The configuration value
     */
    function setMarketConfig(bytes32 marketId, bytes32 key, bytes32 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMarketConfig(marketId, key, value);
        emit SetMarketConfig(marketId, key, value);
    }

    /**
     * @notice Sets a pool-specific configuration value
     * @param pool The address of the pool
     * @param key The configuration key
     * @param value The configuration value
     */
    function setPoolConfig(address pool, bytes32 key, bytes32 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPoolConfigs(pool, key, value);
        emit SetCollateralPoolConfig(pool, key, value);
    }

    /**
     * @notice Sets the price for an oracle ID using specified provider, the provider must be whitelisted by `setOracleProvider`
     * @param oracleId The ID of the oracle
     * @param provider The address of the oracle provider
     * @param oracleCalldata The calldata to be passed to the oracle
     */
    function setPrice(
        bytes32 oracleId,
        address provider,
        bytes memory oracleCalldata
    ) external virtual onlyRole(ORDER_BOOK_ROLE) {
        (uint256 price, uint256 timestamp) = _setPrice(oracleId, provider, oracleCalldata);
        emit SetPrice(oracleId, provider, oracleCalldata, price, timestamp);
    }
}
