// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

enum OrderType {
    None, // 0
    PositionOrder, // 1
    LiquidityOrder, // 2
    WithdrawalOrder, // 3
    AdlOrder // 4
}

// position order flags
uint256 constant POSITION_OPEN = 0x80; // this flag means open-position; otherwise close-position
uint256 constant POSITION_MARKET_ORDER = 0x40; // this flag only affects order expire time and shows a better effect on UI
uint256 constant POSITION_WITHDRAW_ALL_IF_EMPTY = 0x20; // this flag means auto withdraw all collateral if position.size == 0
uint256 constant POSITION_TRIGGER_ORDER = 0x10; // this flag means this is a trigger order (ex: stop-loss order). otherwise this is a limit order (ex: take-profit order)
// 0x08 was POSITION_TPSL_STRATEGY. not suitable for mux3
// 0x04 was POSITION_SHOULD_REACH_MIN_PROFIT. not suitable for mux3
uint256 constant POSITION_AUTO_DELEVERAGE = 0x02; // denotes that this order is an auto-deleverage order
uint256 constant POSITION_UNWRAP_ETH = 0x100; // unwrap WETH into ETH. only valid when fill close-position, or cancel open-position, or fill liquidity, or cancel liquidity
uint256 constant POSITION_WITHDRAW_PROFIT = 0x200; // withdraw profit - fee. only valid when fill close-position

struct OrderData {
    uint64 id;
    address account;
    OrderType orderType;
    uint8 version;
    uint256 placeOrderTime;
    bytes payload;
}

struct OrderBookStorage {
    address mux3Facet;
    uint64 nextOrderId;
    mapping(uint64 => OrderData) orderData;
    EnumerableSetUpgradeable.UintSet orders;
    mapping(address => EnumerableSetUpgradeable.UintSet) userOrders;
    mapping(bytes32 => EnumerableSetUpgradeable.UintSet) tpslOrders;
    uint32 sequence; // will be 0 after 0xffffffff
    mapping(address => bool) priceProviders;
    address weth;
    mapping(address => uint256) previousTokenBalance;
    bytes32[50] __gap;
}

struct PositionOrderParams {
    bytes32 positionId;
    bytes32 marketId;
    uint256 size;
    uint256 flags; // see "constant POSITION_*"
    uint256 limitPrice; // decimals = 18
    uint256 expiration; // timestamp. decimals = 0
    address lastConsumedToken; // when paying fees or losses (for both open and close positions), this token will be consumed last. can be 0 if no preference
    // when openPosition
    // * collateralToken == 0 means do not deposit collateral
    // * collateralToken != 0 means to deposit collateralToken as collateral
    // * deduct fees
    // * open positions
    address collateralToken; // only valid when flags.POSITION_OPEN
    uint256 collateralAmount; // only valid when flags.POSITION_OPEN. erc20.decimals
    // when closePosition, pnl and fees
    // * realize pnl
    // * deduct fees
    // * flags.POSITION_WITHDRAW_PROFIT means also withdraw (profit - fee)
    // * withdrawUsd means to withdraw collateral. this is independent of flags.POSITION_WITHDRAW_PROFIT
    // * flags.POSITION_UNWRAP_ETH means to unwrap WETH into ETH
    uint256 withdrawUsd; // only valid when close a position
    address withdrawSwapToken; // only valid when close a position and withdraw. try to swap to this token
    uint256 withdrawSwapSlippage; // only valid when close a position and withdraw. slippage tolerance for withdrawSwapToken. if swap cannot achieve this slippage, swap will be skipped
    // tpsl strategy, only valid when openPosition
    uint256 tpPriceDiff; // take-profit price will be marketPrice * diff. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY
    uint256 slPriceDiff; // stop-loss price will be marketPrice * diff. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY
    uint256 tpslExpiration; // timestamp. decimals = 0. only valid when flags.POSITION_TPSL_STRATEGY
    uint256 tpslFlags; // POSITION_WITHDRAW_ALL_IF_EMPTY, POSITION_WITHDRAW_PROFIT, POSITION_UNWRAP_ETH. only valid when flags.POSITION_TPSL_STRATEGY
    address tpslWithdrawSwapToken; // only valid when flags.POSITION_TPSL_STRATEGY
    uint256 tpslWithdrawSwapSlippage; // only valid when flags.POSITION_TPSL_STRATEGY
}

struct LiquidityOrderParams {
    address poolAddress;
    uint256 rawAmount; // erc20.decimals
    bool isAdding;
    bool isUnwrapWeth;
}

struct WithdrawalOrderParams {
    bytes32 positionId;
    address tokenAddress;
    uint256 rawAmount; // erc20.decimals
    bool isUnwrapWeth;
    address lastConsumedToken; // this token will be consumed last. can be 0 if no preference
    address withdrawSwapToken; // try to swap to this token
    uint256 withdrawSwapSlippage; // slippage tolerance for withdrawSwapToken. if swap cannot achieve this slippage, swap will be skipped
}

struct WithdrawAllOrderParams {
    bytes32 positionId;
    bool isUnwrapWeth;
    address withdrawSwapToken;
    uint256 withdrawSwapSlippage;
}

struct AdlOrderParams {
    bytes32 positionId;
    uint256 size; // 1e18
    uint256 price; // 1e18
    address profitToken;
    bool isUnwrapWeth;
}

interface IOrderBook {
    event UpdateSequence(uint32 sequence);
    event CancelOrder(address indexed account, uint64 indexed orderId, OrderData orderData);
    event NewLiquidityOrder(address indexed account, uint64 indexed orderId, LiquidityOrderParams params);
    event NewPositionOrder(address indexed account, uint64 indexed orderId, PositionOrderParams params);
    event NewWithdrawalOrder(address indexed account, uint64 indexed orderId, WithdrawalOrderParams params);
    event FillOrder(address indexed account, uint64 indexed orderId, OrderData orderData);
    event FillAdlOrder(address indexed account, AdlOrderParams params);

    function multicall(bytes[] calldata proxyCalls) external payable returns (bytes[] memory results);

    function wrapNative() external payable;

    function transferToken(address token, uint256 amount) external;

    function transferTokenFrom(address from, address token, uint256 amount) external;

    function cancelOrder(uint64 orderId) external;

    function setInitialLeverage(bytes32 positionId, bytes32 marketId, uint256 initialLeverage) external;

    function placePositionOrder(PositionOrderParams memory orderParams, bytes32 referralCode) external;

    function placeLiquidityOrder(LiquidityOrderParams memory orderParams) external;

    function placeWithdrawalOrder(WithdrawalOrderParams memory orderParams) external;

    function withdrawAllCollateral(WithdrawAllOrderParams memory orderParams) external;

    function depositCollateral(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount // token decimals
    ) external;
}

interface IOrderBookGetter {
    function nextOrderId() external view returns (uint64);

    function sequence() external view returns (uint64);

    function configValue(bytes32 key) external view returns (bytes32);

    function getOrder(uint64 orderId) external view returns (OrderData memory, bool);

    function getOrders(
        uint256 begin,
        uint256 end
    ) external view returns (OrderData[] memory orderDataArray, uint256 totalCount);

    function getOrdersOf(
        address user,
        uint256 begin,
        uint256 end
    ) external view returns (OrderData[] memory orderDataArray, uint256 totalCount);
}
