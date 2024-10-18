// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IMux3Core.sol";
import "../interfaces/IMarket.sol";
import "../interfaces/IPositionAccount.sol";
import "../interfaces/ICollateralPool.sol";

contract Mux3Store is AccessControlEnumerableUpgradeable {
    mapping(bytes32 => bytes32) internal _configs;
    // whitelist
    address[] internal _collateralTokenList;
    mapping(address => CollateralTokenInfo) internal _collateralTokens;
    // accounts
    mapping(bytes32 => PositionAccountInfo) internal _positionAccounts;
    mapping(address => EnumerableSetUpgradeable.Bytes32Set)
        internal _positionAccountLists;
    // pools
    EnumerableSetUpgradeable.AddressSet internal _collateralPoolList;
    // markets
    mapping(bytes32 => MarketInfo) internal _markets;
    EnumerableSetUpgradeable.Bytes32Set internal _marketList;
    // pool imp
    address internal _collateralPoolImplementation;
    // oracle
    mapping(address => bool) internal _oracleProviders;

    bytes32[50] private __gaps;

    function __Mux3Store_init(address admin) internal onlyInitializing {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
}
