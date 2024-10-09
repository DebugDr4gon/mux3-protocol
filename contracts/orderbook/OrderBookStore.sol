// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../interfaces/IConfigTable.sol";
import "../interfaces/IOrderBook.sol";
import "../libraries/LibTypeCast.sol";

contract OrderBookStore is Initializable, AccessControlEnumerableUpgradeable {
    using LibTypeCast for bytes32;

    ConfigTable internal _configTable;
    OrderBookStorage internal _storage; // should be the last variable before __gap
    bytes32[50] __gap;

    function __OrderBookStore_init() internal onlyInitializing {}
}
