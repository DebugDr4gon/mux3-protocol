// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IPoolToken is IERC20Upgradeable, IERC20MetadataUpgradeable {
    function mint(address receiver, uint256 amount) external;

    function burn(address receiver, uint256 amount) external;
}
