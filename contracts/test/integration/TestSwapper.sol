// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../interfaces/ISwapper.sol";
import "../../libraries/LibUniswap3.sol";
import "../../libraries/LibBalancer2.sol";

contract TestSwapper {
    function quoteUniswap3(
        address swapRouter,
        bytes memory path,
        uint256 amountIn
    ) external returns (bool success, uint256 amountOut) {
        return LibUniswap3.quote(swapRouter, path, amountIn);
    }

    function swapUniswap3(
        address swapRouter,
        bytes memory path,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (bool success, uint256 amountOut) {
        return LibUniswap3.swap(swapRouter, path, tokenIn, tokenOut, amountIn, 0);
    }

    function quoteBalancer2(
        address vault,
        IBalancer2Asset[] memory assets,
        IBalancer2Vault.BatchSwapStep[] memory swaps,
        uint256 amountIn
    ) external returns (bool success, uint256 amountOut) {
        LibBalancer2.Args memory args = LibBalancer2.Args({ assets: assets, swaps: swaps });
        bytes memory path = abi.encode(args);
        return LibBalancer2.quote(vault, path, amountIn);
    }

    function swapBalancer2(
        address vault,
        IBalancer2Asset[] memory assets,
        IBalancer2Vault.BatchSwapStep[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (bool success, uint256 amountOut) {
        LibBalancer2.Args memory args = LibBalancer2.Args({ assets: assets, swaps: swaps });
        bytes memory path = abi.encode(args);
        return LibBalancer2.swap(vault, path, tokenIn, tokenOut, amountIn, 0);
    }
}
