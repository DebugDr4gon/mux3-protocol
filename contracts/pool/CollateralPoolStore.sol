// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "../interfaces/IMux3Core.sol";
import "../interfaces/ICollateralPool.sol";
import "../interfaces/IConfigTable.sol";
import "./CollateralPoolToken.sol";

contract CollateralPoolStore is CollateralPoolToken {
    ConfigTable internal _configTable;
    address internal _core;
    IERC20Upgradeable internal _collateralToken;
    uint8 internal _collateralDecimals;
    uint256 internal _liquidityBalance;

    EnumerableSetUpgradeable.Bytes32Set internal _marketIds;
    mapping(bytes32 => MarketState) internal _marketStates;

    bytes32[50] private _gaps;

    function __CollateralPoolStore_init(
        address core,
        address collateralToken,
        uint8 collateralDecimals
    ) internal onlyInitializing {
        _core = core;
        _collateralToken = IERC20Upgradeable(collateralToken);
        _collateralDecimals = collateralDecimals;
    }
}
