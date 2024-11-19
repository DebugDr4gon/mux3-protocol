// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface ISwapper {
    function swapAndTransfer(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        address receiver,
        bool isUnwrapWeth
    ) external returns (bool success, uint256 amountOut);
}
