// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

bytes32 constant MCO_LIQUIDITY_LOCK_PERIOD = keccak256(
    "MCO_LIQUIDITY_LOCK_PERIOD"
);
bytes32 constant MCO_POSITION_ORDER_PAUSED = keccak256(
    "MCO_POSITION_ORDER_PAUSED"
);
bytes32 constant MCO_LIQUIDITY_ORDER_PAUSED = keccak256(
    "MCO_LIQUIDITY_ORDER_PAUSED"
);
bytes32 constant MCO_WITHDRAWAL_ORDER_PAUSED = keccak256(
    "MCO_WITHDRAWAL_ORDER_PAUSED"
);
bytes32 constant MCO_MARKET_ORDER_TIMEOUT = keccak256(
    "MCO_MARKET_ORDER_TIMEOUT"
);
bytes32 constant MCO_LIMIT_ORDER_TIMEOUT = keccak256("MCO_LIMIT_ORDER_TIMEOUT");
bytes32 constant MCO_REFERRAL_MANAGER = keccak256("MCO_REFERRAL_MANAGER");
bytes32 constant MCO_CANCEL_COOL_DOWN = keccak256("MCO_CANCEL_COOL_DOWN");
bytes32 constant MCO_UNWRAP_WETH_GAS_LIMIT = keccak256(
    "MCO_UNWRAP_WETH_GAS_LIMIT"
);

enum OrderType {
    None, // 0
    PositionOrder, // 1
    LiquidityOrder, // 2
    WithdrawalOrder, // 3
    AdlOrder // 4
}

// position order flags
uint256 constant POSITION_OPEN = 0x80; // this flag means open-position; otherwise close-position
uint256 constant POSITION_MARKET_ORDER = 0x40; // this flag only affects order expire time and show a better effect on UI
uint256 constant POSITION_WITHDRAW_ALL_IF_EMPTY = 0x20; // this flag means auto withdraw all collateral if position.size == 0
uint256 constant POSITION_TRIGGER_ORDER = 0x10; // this flag means this is a trigger order (ex: stop-loss order). otherwise this is a limit order (ex: take-profit order)
uint256 constant POSITION_TPSL_STRATEGY = 0x08; // for open-position-order, this flag auto place take-profit and stop-loss orders when open-position-order fills.
//                                                 for close-position-order, this flag means ignore limitPrice and profitToken, and use tpPrice, slPrice, tpslProfitToken instead.
// 0x04 was POSITION_SHOULD_REACH_MIN_PROFIT. not suitable for mux3
uint256 constant POSITION_AUTO_DELEVERAGE = 0x02; // denotes that this order is an auto-deleverage order
uint256 constant POSITION_UNWRAP_ETH = 0x100; // unwrap WETH into ETH. only valid when fill close-position, or cancel open-position, or fill liquidity, or cancel liquidity

uint256 constant MAX_TP_SL_ORDERS = 32;

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
    bytes32 marketId;
    bytes32 positionId;
    uint256 size;
    uint256 flags; // see "constant POSITION_*"
    uint256 limitPrice; // 1e18
    uint256 tpPrice; // take-profit price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
    uint256 slPrice; // stop-loss price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
    uint256 expiration; // 1e0, timestamp
    uint256 tpslExpiration; // 1e0, timestamp
    address profitToken; // only valid when close a position and the trader wants to swap
    address tpslProfitToken; // only valid when flags.POSITION_TPSL_STRATEGY.
    address collateralToken; // deposit or withdraw. optional.
    uint256 collateralAmount; // deposit or withdraw. optional. erc20.decimals
    uint256 initialLeverage; // only valid when flags.POSITION_OPEN. 1e18
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
    event CancelOrder(
        address indexed account,
        uint64 indexed orderId,
        OrderData orderData
    );
    event NewLiquidityOrder(
        address indexed account,
        uint64 indexed orderId,
        LiquidityOrderParams params
    );
    event NewPositionOrder(
        address indexed account,
        uint64 indexed orderId,
        PositionOrderParams params
    );
    event NewWithdrawalOrder(
        address indexed account,
        uint64 indexed orderId,
        WithdrawalOrderParams params
    );
    event FillOrder(
        address indexed account,
        uint64 indexed orderId,
        OrderData orderData
    );
    event FillAdlOrder(address indexed account, AdlOrderParams params);

    function transferTokenFrom(
        address from,
        address token,
        uint256 amount
    ) external;

    function placePositionOrder(
        PositionOrderParams memory orderParams,
        bytes32 referralCode
    ) external;

    function cancelOrder(uint64 orderId) external;
}

interface IOrderBookGetter {
    function getOrder(
        uint64 orderId
    ) external view returns (OrderData memory, bool);
}
