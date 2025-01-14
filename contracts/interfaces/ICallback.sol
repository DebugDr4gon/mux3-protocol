// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface ICallback {
    function afterLiquidityOrderFilled(
        uint64 orderId,
        uint256 assetAmount,
        uint256 lpAmount,
        uint256 assetPrice,
        uint256 mlpPrice
    ) external;
}
