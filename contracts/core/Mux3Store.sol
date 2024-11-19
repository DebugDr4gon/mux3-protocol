// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IMux3Core.sol";
import "../interfaces/IMarket.sol";
import "../interfaces/ICollateralPool.sol";
import "../libraries/LibMux3Roles.sol";

contract Mux3Store is Mux3RolesStore {
    mapping(bytes32 => bytes32) internal _configs;
    // collaterals
    address[] internal _collateralTokenList;
    mapping(address => CollateralTokenInfo) internal _collateralTokens;
    // accounts
    mapping(bytes32 => PositionAccountInfo) internal _positionAccounts; // positionId => PositionAccountInfo
    mapping(address => EnumerableSetUpgradeable.Bytes32Set) internal _positionIdListOf; // trader => positionIds. this list never recycles (because Trader can store some settings in position accounts which are never destroyed)
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
    mapping(bytes32 => bool) internal _strictStableIds;
    // accounts
    EnumerableSetUpgradeable.Bytes32Set internal _activatePositionIdList; // positionId that has positions. positionId with only collateral may not be in this list

    bytes32[47] private __gaps;
}
