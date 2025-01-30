// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ISwapRouter as IUniswapV3SwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IQuoter as IUniswapV3Quoter } from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "./LibUniswap3Path.sol";
import "../interfaces/ISwapper.sol";

library LibUniswap3 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 constant MIN_PATH_LENGTH = 20 + 3 + 20;

    /**
     * @dev Check if path is swapping from tokenIn to tokenOut
     */
    function isValidPath(address tokenIn, address tokenOut, bytes memory path) internal pure returns (bool) {
        if (tokenIn == tokenOut) {
            return false;
        }
        if (path.length < MIN_PATH_LENGTH) {
            return false;
        }
        (address realTokenIn, , ) = LibUniswap3Path.decodeFirstPool(path);
        if (realTokenIn != tokenIn) {
            return false;
        }
        while (LibUniswap3Path.hasMultiplePools(path)) {
            path = LibUniswap3Path.skipToken(path);
        }
        (, address realTokenOut, ) = LibUniswap3Path.decodeFirstPool(path);
        if (realTokenOut != tokenOut) {
            return false;
        }
        return true;
    }

    function quote(
        address quoter,
        bytes memory path,
        uint256 amountIn
    ) internal returns (bool success, uint256 bestOutAmount) {
        require(address(quoter) != address(0), "Swapper::uniswap3Quoter not set");
        try IUniswapV3Quoter(quoter).quoteExactInput(path, amountIn) returns (uint256 outAmount) {
            success = true;
            bestOutAmount = outAmount;
        } catch {
            // probably insufficient liquidity, not a big deal
            emit ISwapper.BrokenUniswap3Path(path, amountIn);
        }
    }

    function swap(
        address swapRouter,
        bytes memory path,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (bool success, uint256 amountOut) {
        require(address(swapRouter) != address(0), "Swapper::uniswap3Router not set");
        // executes the swap on uniswap pool
        SafeERC20Upgradeable.forceApprove(IERC20Upgradeable(tokenIn), address(swapRouter), amountIn);
        // exact input swap to convert exact amount of tokens into usdc
        IUniswapV3SwapRouter.ExactInputParams memory params = IUniswapV3SwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });
        // since exact input swap tokens used = token amount passed
        try IUniswapV3SwapRouter(swapRouter).exactInput(params) returns (uint256 _amountOut) {
            amountOut = _amountOut;
            success = true;
        } catch {}
        emit ISwapper.Uniswap3Call(tokenIn, tokenOut, amountIn, amountOut);
    }
}
