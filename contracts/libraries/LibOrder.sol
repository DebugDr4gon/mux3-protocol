// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../interfaces/IOrderBook.sol";

library LibOrder {
    function encodePositionOrder(
        PositionOrderParams memory orderParams,
        uint64 orderId,
        address account,
        uint64 blockTimestamp,
        uint64 gasFeeGwei
    ) internal pure returns (OrderData memory orderData) {
        orderData.orderType = OrderType.PositionOrder;
        orderData.id = orderId;
        orderData.version = 1;
        orderData.placeOrderTime = blockTimestamp;
        orderData.account = account;
        orderData.gasFeeGwei = gasFeeGwei;
        orderData.payload = abi.encode(orderParams);
    }

    function decodePositionOrder(
        OrderData memory orderData
    ) internal pure returns (PositionOrderParams memory orderParams) {
        require(orderData.orderType == OrderType.PositionOrder, "Unexpected order type");
        require(orderData.version == 1, "Unexpected order version");
        require(orderData.payload.length == 18 * 32, "Unexpected order payload length");
        orderParams = abi.decode(orderData.payload, (PositionOrderParams));
    }

    function encodeLiquidityOrder(
        LiquidityOrderParams memory orderParams,
        uint64 orderId,
        address account,
        uint64 blockTimestamp,
        uint64 gasFeeGwei
    ) internal pure returns (OrderData memory orderData) {
        orderData.orderType = OrderType.LiquidityOrder;
        orderData.id = orderId;
        orderData.version = 1;
        orderData.placeOrderTime = blockTimestamp;
        orderData.account = account;
        orderData.gasFeeGwei = gasFeeGwei;
        orderData.payload = abi.encode(orderParams);
    }

    function decodeLiquidityOrder(
        OrderData memory orderData
    ) internal pure returns (LiquidityOrderParams memory orderParams) {
        require(orderData.orderType == OrderType.LiquidityOrder, "Unexpected order type");
        require(orderData.version == 1, "Unexpected order version");
        require(orderData.payload.length == 4 * 32, "Unexpected order payload length");
        orderParams = abi.decode(orderData.payload, (LiquidityOrderParams));
    }

    function encodeWithdrawalOrder(
        WithdrawalOrderParams memory orderParams,
        uint64 orderId,
        uint64 blockTimestamp,
        address account,
        uint64 gasFeeGwei
    ) internal pure returns (OrderData memory orderData) {
        orderData.orderType = OrderType.WithdrawalOrder;
        orderData.id = orderId;
        orderData.version = 1;
        orderData.placeOrderTime = blockTimestamp;
        orderData.account = account;
        orderData.gasFeeGwei = gasFeeGwei;
        orderData.payload = abi.encode(orderParams);
    }

    function decodeWithdrawalOrder(
        OrderData memory orderData
    ) internal pure returns (WithdrawalOrderParams memory orderParams) {
        require(orderData.orderType == OrderType.WithdrawalOrder, "Unexpected order type");
        require(orderData.version == 1, "Unexpected order version");
        require(orderData.payload.length == 7 * 32, "Unexpected order payload length");
        orderParams = abi.decode(orderData.payload, (WithdrawalOrderParams));
    }

    function encodeRebalanceOrder(
        RebalanceOrderParams memory orderParams,
        uint64 orderId,
        uint64 blockTimestamp,
        address rebalancer
    ) internal pure returns (OrderData memory orderData) {
        orderData.orderType = OrderType.RebalanceOrder;
        orderData.id = orderId;
        orderData.version = 1;
        orderData.placeOrderTime = blockTimestamp;
        orderData.account = rebalancer;
        orderData.payload = abi.encode(orderParams);
    }

    function decodeRebalanceOrder(
        OrderData memory orderData
    ) internal pure returns (RebalanceOrderParams memory orderParams) {
        require(orderData.orderType == OrderType.RebalanceOrder, "Unexpected order type");
        require(orderData.version == 1, "Unexpected order version");
        require(orderData.payload.length >= 5 * 32, "Unexpected order payload length"); // poolAddress, token0, rawAmount0, maxRawAmount1, userData
        orderParams = abi.decode(orderData.payload, (RebalanceOrderParams));
    }

    function isOpenPosition(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_OPEN) != 0;
    }

    function isMarketOrder(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_MARKET_ORDER) != 0;
    }

    function isWithdrawAllIfEmpty(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_WITHDRAW_ALL_IF_EMPTY) != 0;
    }

    function isTriggerOrder(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_TRIGGER_ORDER) != 0;
    }

    function isAdl(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_AUTO_DELEVERAGE) != 0;
    }

    function isUnwrapWeth(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_UNWRAP_ETH) != 0;
    }

    function isWithdrawProfit(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_WITHDRAW_PROFIT) != 0;
    }
}
