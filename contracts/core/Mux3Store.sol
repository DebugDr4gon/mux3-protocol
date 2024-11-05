// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IMux3Core.sol";
import "../interfaces/IMarket.sol";
import "../interfaces/ICollateralPool.sol";
import "../libraries/LibMux3Roles.sol";

contract Mux3Store is Mux3RolesStore {
    mapping(bytes32 => bytes32) internal _configs;
    // whitelist
    address[] internal _collateralTokenList;
    mapping(address => CollateralTokenInfo) internal _collateralTokens;
    // accounts
    mapping(bytes32 => PositionAccountInfo) internal _positionAccounts;
    mapping(address => EnumerableSetUpgradeable.Bytes32Set) internal _positionAccountLists;
    // pools
    EnumerableSetUpgradeable.AddressSet internal _collateralPoolList;
    // markets
    mapping(bytes32 => MarketInfo) internal _markets;
    EnumerableSetUpgradeable.Bytes32Set internal _marketList;
    // pool imp
    address internal _collateralPoolImplementation;
    // oracle
    mapping(address => bool) internal _oracleProviders;
    address internal _weth;

    bytes32[49] private __gaps;
}
