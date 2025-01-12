// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface ISwapper {
    event BrokenUniswap3Path(bytes path, uint256 amountIn);
    event Uniswap3Call(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    event BrokenBalancer2Path(bytes path, uint256 amountIn);
    event Balancer2Call(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    function swapAndTransfer(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        address receiver,
        bool isUnwrapWeth
    ) external returns (bool success, uint256 amountOut);
}
