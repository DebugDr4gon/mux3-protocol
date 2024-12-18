// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// ==================== core ====================

// borrowingFeeRate = MC_BORROWING_BASE_APY + E^(MCP_BORROWING_K * util + MCP_BORROWING_B),
// where util = reservedUsd / poolSizeUsd. decimals = 18
bytes32 constant MC_BORROWING_BASE_APY = keccak256("MC_BORROWING_BASE_APY");

// an interval in seconds. CollateralPool collects borrowing fee every interval
bytes32 constant MC_BORROWING_INTERVAL = keccak256("MC_BORROWING_INTERVAL");

// an IMux3FeeDistributor address that receives positionFee, borrowingFee and liquidityFee
bytes32 constant MC_FEE_DISTRIBUTOR = keccak256("MC_FEE_DISTRIBUTOR");

// an ISwapper address that swaps collateral/profit to another collateral token when requested by trader
bytes32 constant MC_SWAPPER = keccak256("MC_SWAPPER");

// for collateral tokens marked as strict stable via IFacetManagement.setStrictStableId,
// oracle prices within the range [1 - MC_STRICT_STABLE_DEVIATION, 1 + MC_STRICT_STABLE_DEVIATION] are normalized to 1.000
// decimals = 18
bytes32 constant MC_STRICT_STABLE_DEVIATION = keccak256("MC_STRICT_STABLE_DEVIATION");

// ==================== market ====================

// positionFee = price * size * MM_POSITION_FEE_RATE when openPosition/closePosition. decimals = 18
bytes32 constant MM_POSITION_FEE_RATE = keccak256("MM_POSITION_FEE_RATE");

// positionFee = price * size * MM_LIQUIDATION_FEE_RATE when liquidatePosition. decimals = 18
bytes32 constant MM_LIQUIDATION_FEE_RATE = keccak256("MM_LIQUIDATION_FEE_RATE");

// when openPosition, require marginBalance >= Σ(price * size * MM_INITIAL_MARGIN_RATE). decimals = 18
bytes32 constant MM_INITIAL_MARGIN_RATE = keccak256("MM_INITIAL_MARGIN_RATE");

// when marginBalance < Σ(price * size * MM_MAINTENANCE_MARGIN_RATE), liquidate is allowed. decimals = 18
bytes32 constant MM_MAINTENANCE_MARGIN_RATE = keccak256("MM_MAINTENANCE_MARGIN_RATE");

// openPosition/closePosition/liquidatePosition size must be a multiple of MM_LOT_SIZE. decimals = 18
bytes32 constant MM_LOT_SIZE = keccak256("MM_LOT_SIZE");

// market price is identified and fetched from oracle using this ID
bytes32 constant MM_ORACLE_ID = keccak256("MM_ORACLE_ID");

// pause trade of a market
bytes32 constant MM_DISABLE_TRADE = keccak256("MM_DISABLE_TRADE");

// pause openPosition of a market. if MM_DISABLE_OPEN && !MM_DISABLE_TRADE, only closePosition is allowed
bytes32 constant MM_DISABLE_OPEN = keccak256("MM_DISABLE_OPEN");

// the maximum open interest limit for a single market. the open interest is constrained by both
// this cap and MCP_ADL_RESERVE_RATE of each pool. decimals = 18
bytes32 constant MM_OPEN_INTEREST_CAP_USD = keccak256("MM_OPEN_INTEREST_CAP_USD");

// ==================== pool ====================

// if not empty, override CollateralPool ERC20 name
bytes32 constant MCP_TOKEN_NAME = keccak256("MCP_TOKEN_NAME");

// if not empty, override CollateralPool ERC20 symbol
bytes32 constant MCP_TOKEN_SYMBOL = keccak256("MCP_TOKEN_SYMBOL");

// liquidityFee = price * liquidity * MCP_LIQUIDITY_FEE_RATE. decimals = 18
bytes32 constant MCP_LIQUIDITY_FEE_RATE = keccak256("MCP_LIQUIDITY_FEE_RATE");

// reject addLiquidity if aumUsdWithoutPnl > MCP_LIQUIDITY_CAP_USD. decimals = 18
bytes32 constant MCP_LIQUIDITY_CAP_USD = keccak256("MCP_LIQUIDITY_CAP_USD");

// borrowingFeeRate = MC_BORROWING_BASE_APY + E^(MCP_BORROWING_K * util + MCP_BORROWING_B), where util = reservedUsd / poolSizeUsd
bytes32 constant MCP_BORROWING_K = keccak256("MCP_BORROWING_K");

// borrowingFeeRate = MC_BORROWING_BASE_APY + E^(MCP_BORROWING_K * util + MCP_BORROWING_B), where util = reservedUsd / poolSizeUsd
bytes32 constant MCP_BORROWING_B = keccak256("MCP_BORROWING_B");

// if true, allocate algorithm will skip this CollateralPool when openPosition
bytes32 constant MCP_IS_DRAINING = keccak256("MCP_IS_DRAINING");

// ==================== pool + market ====================

// reserve = price * positions * MCP_ADL_RESERVE_RATE. affects borrowing fee rate and open interest.
// the open interest is constrained by both this rate and MM_OPEN_INTEREST_CAP_USD of the market. decimals = 18
bytes32 constant MCP_ADL_RESERVE_RATE = keccak256("MCP_ADL_RESERVE_RATE");

// position pnl is capped at entryPrice * size * MCP_ADL_MAX_PNL_RATE. decimals = 18
bytes32 constant MCP_ADL_MAX_PNL_RATE = keccak256("MCP_ADL_MAX_PNL_RATE");

// if upnl > entryPrice * size * MCP_ADL_TRIGGER_RATE, ADL is allowed. decimals = 18
bytes32 constant MCP_ADL_TRIGGER_RATE = keccak256("MCP_ADL_TRIGGER_RATE");

// ==================== order book ====================

// only allow fillLiquidityOrder after this seconds
bytes32 constant MCO_LIQUIDITY_LOCK_PERIOD = keccak256("MCO_LIQUIDITY_LOCK_PERIOD");

// pause position order
bytes32 constant MCO_POSITION_ORDER_PAUSED = keccak256("MCO_POSITION_ORDER_PAUSED");

// pause liquidity order
bytes32 constant MCO_LIQUIDITY_ORDER_PAUSED = keccak256("MCO_LIQUIDITY_ORDER_PAUSED");

// pause withdrawal order
bytes32 constant MCO_WITHDRAWAL_ORDER_PAUSED = keccak256("MCO_WITHDRAWAL_ORDER_PAUSED");

// timeout for market order. after this seconds, Broker can cancel the order
bytes32 constant MCO_MARKET_ORDER_TIMEOUT = keccak256("MCO_MARKET_ORDER_TIMEOUT");

// timeout for limit order. after this seconds, Broker can cancel the order
bytes32 constant MCO_LIMIT_ORDER_TIMEOUT = keccak256("MCO_LIMIT_ORDER_TIMEOUT");

// an IReferralManager address
bytes32 constant MCO_REFERRAL_MANAGER = keccak256("MCO_REFERRAL_MANAGER");

// Trader can not cancelOrder before this number of seconds has elapsed
bytes32 constant MCO_CANCEL_COOL_DOWN = keccak256("MCO_CANCEL_COOL_DOWN");

// when calling fillPositionOrder, fillLiquidityOrder, fillWithdrawalOrder, send (MCO_ORDER_GAS_FEE_GWEI * 1e9) ETH
// to Broker as a gas compensation
bytes32 constant MCO_ORDER_GAS_FEE_GWEI = keccak256("MCO_ORDER_GAS_FEE_GWEI");

// minimum order value in USD for adding/removing liquidity
bytes32 constant MCO_MIN_LIQUIDITY_ORDER_USD = keccak256("MCO_MIN_LIQUIDITY_ORDER_USD");
