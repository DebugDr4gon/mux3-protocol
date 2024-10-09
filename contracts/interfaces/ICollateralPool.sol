// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

bytes32 constant MCP_SYMBOL = keccak256("MCP_SYMBOL");
bytes32 constant MCP_LIQUIDITY_FEE_RATE = keccak256("MCP_LIQUIDITY_FEE_RATE");
bytes32 constant MCP_LIQUIDITY_CAP_USD = keccak256("MCP_LIQUIDITY_CAP_USD");
bytes32 constant MCP_BORROWING_K = keccak256("MCP_BORROWING_K");
bytes32 constant MCP_BORROWING_B = keccak256("MCP_BORROWING_B");
bytes32 constant MCP_IS_HIGH_PRIORITY = keccak256("MCP_IS_HIGH_PRIORITY");
bytes32 constant MCP_ADL_RESERVE_RATE = keccak256("MCP_ADL_RESERVE_RATE");
bytes32 constant MCP_ADL_MAX_PNL_RATE = keccak256("MCP_ADL_MAX_PNL_RATE");
bytes32 constant MCP_ADL_TRIGGER_RATE = keccak256("MCP_ADL_TRIGGER_RATE");

struct MarketState {
    bool isLong;
    uint256 totalSize;
    uint256 averageEntryPrice;
}

interface ICollateralPool {
    event AddLiquidity(
        address indexed account,
        address indexed tokenAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    );
    event AddLiquidityFromFee(
        address tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    event RemoveLiquidity(
        address indexed account,
        address indexed collateralAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    );
    event OpenPosition(
        bytes32 marketId,
        uint256 size,
        uint256 averageEntryPrice,
        uint256 totalSize
    );
    event ClosePosition(bytes32 marketId, uint256 size, uint256 totalSize);
    event ReceiveFee(address token, uint256 rawAmount);
    event SetConfig(bytes32 key, bytes32 value);
    event CollectFee(address token, uint256 wad);

    function setConfig(bytes32 key, bytes32 value) external;

    function collateralToken() external view returns (address);

    function borrowingFeeRateApy() external view returns (uint256 feeRateApy);

    function markets() external view returns (bytes32[] memory);

    function setMarket(bytes32 marketId, bool isLong) external;

    function openPosition(bytes32 marketId, uint256 size) external;

    function closePosition(bytes32 marketId, uint256 size) external;

    function addLiquidity(
        address account,
        uint256 collaterals
    ) external returns (uint256 shares);

    function removeLiquidity(
        address account,
        uint256 shares
    ) external returns (uint256 collateralAmount);

    function receiveFee(
        address token,
        uint256 rawAmount // token.decimals
    ) external;
}
