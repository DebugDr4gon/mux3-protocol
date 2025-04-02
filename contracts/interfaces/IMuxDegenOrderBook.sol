// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IMuxDegenOrderBook {
    struct PositionOrderParams {
        bytes32 subAccountId; // 160 + 8 + 8 + 8 = 184
        uint96 collateral; // erc20.decimals
        uint96 size; // 1e18
        uint96 price; // 1e18
        uint96 tpPrice; // take-profit price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
        uint96 slPrice; // stop-loss price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
        uint32 expiration; // 1e0 seconds
        uint32 tpslExpiration; // 1e0 seconds
        uint8 profitTokenId;
        uint8 tpslProfitTokenId; // only valid when flags.POSITION_TPSL_STRATEGY.
        uint8 flags;
    }

    struct WithdrawalOrderParams {
        bytes32 subAccountId; // 160 + 8 + 8 + 8 = 184
        uint96 rawAmount; // erc20.decimals
        uint8 profitTokenId; // always 0. not supported in DegenPool. only for compatibility
        bool isProfit; // always false. not supported in DegenPool. only for compatibility
    }

    enum OrderType {
        None, // 0
        PositionOrder, // 1
        LiquidityOrder, // 2
        WithdrawalOrder // 3
    }

    struct OrderData {
        address account;
        uint64 id;
        OrderType orderType;
        uint8 version;
        uint32 placeOrderTime;
        bytes payload;
    }

    function getOrder(uint64 orderId) external view returns (OrderData memory, bool);

    function placePositionOrder(PositionOrderParams memory orderParams, bytes32 referralCode) external;

    function placeWithdrawalOrder(WithdrawalOrderParams memory orderParams) external;

    function cancelOrder(uint64 orderId) external;

    function withdrawAllCollateral(bytes32 subAccountId) external;

    function depositCollateral(bytes32 subAccountId, uint256 collateralAmount) external;
}
