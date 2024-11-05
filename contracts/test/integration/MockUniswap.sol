// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./MockUniswapPath.sol";

contract MockUniswapV3 {
    address usdc;
    address weth;
    address wbtc;
    address arb;

    constructor(address usdc_, address weth_, address wbtc_, address arb_) {
        usdc = usdc_;
        weth = weth_;
        wbtc = wbtc_;
        arb = arb_;
    }

    function exactInput(ISwapRouter.ExactInputParams memory params) external returns (uint256 amountOut) {
        uint256 amountIn = params.amountIn;
        address tokenIn;
        address tokenOut;
        (tokenIn, tokenOut, amountOut) = _price(params.path, amountIn);
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(params.recipient, amountOut);
        require(amountOut >= params.amountOutMinimum, "UniswapV3: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function quoteExactInput(bytes memory path, uint256 amountIn) external view returns (uint256 amountOut) {
        (, , amountOut) = _price(path, amountIn);
    }

    function _price(
        bytes memory path,
        uint256 amountIn
    ) internal view returns (address tokenIn, address tokenOut, uint256 amountOut) {
        (tokenIn, , ) = Path.decodeFirstPool(path);
        while (Path.hasMultiplePools(path)) {
            path = Path.skipToken(path);
        }
        (, tokenOut, ) = Path.decodeFirstPool(path);
        if (tokenIn == weth && tokenOut == usdc) {
            // assume 3000
            amountOut = (amountIn * 3000) / 1e12;
        } else if (tokenIn == usdc && tokenOut == weth) {
            // assume 1/3000
            amountOut = (amountIn * 1e12) / 3000;
        } else if (tokenIn == wbtc && tokenOut == usdc) {
            // assume 50000
            amountOut = (amountIn * 50000) / 1e10;
        } else if (tokenIn == usdc && tokenOut == wbtc) {
            // assume 1/50000
            amountOut = (amountIn * 1e10) / 50000;
        } else if (tokenIn == arb && tokenOut == usdc) {
            // assume 1
            amountOut = (amountIn * 1) / 1e12;
        } else if (tokenIn == usdc && tokenOut == arb) {
            // assume 1/1
            amountOut = (amountIn * 1e12) / 1;
        } else {
            revert("Unsupported pair");
        }
    }
}
