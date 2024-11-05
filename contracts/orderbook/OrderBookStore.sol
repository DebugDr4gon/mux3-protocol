// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../interfaces/IOrderBook.sol";
import "../libraries/LibTypeCast.sol";

contract OrderBookStore is Initializable, AccessControlEnumerableUpgradeable {
    using LibTypeCast for bytes32;

    mapping(bytes32 => bytes32) internal _configTable;
    OrderBookStorage internal _storage; // should be the last variable before __gap
    bytes32[50] __gap;

    function __OrderBookStore_init() internal onlyInitializing {}
}
