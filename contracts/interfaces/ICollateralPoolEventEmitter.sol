// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface ICollateralPoolEventEmitter {
    // add liquidity, mint shares
    event AddLiquidity(
        address indexed pool,
        address indexed account,
        address indexed tokenAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    );
    // burn shares, remove liquidity
    event RemoveLiquidity(
        address indexed pool,
        address indexed account,
        address indexed collateralAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    );
    event Rebalance(
        address indexed pool,
        address rebalancer,
        address indexed token0,
        address indexed token1,
        uint256 price0, // 1e18
        uint256 price1, // 1e18
        uint256 amount0, // 1e18
        uint256 amount1 // 1e18
    );
    // add liquidity without mint shares. called by fees, loss, swap
    event LiquidityBalanceIn(
        address indexed pool,
        address indexed tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    // remove liquidity without burn shares. called by swap
    event LiquidityBalanceOut(
        address indexed pool,
        address indexed tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    event OpenPosition(
        address indexed pool,
        bytes32 indexed marketId,
        uint256 size,
        uint256 averageEntryPrice,
        uint256 totalSize
    );
    event ClosePosition(address indexed pool, bytes32 indexed marketId, uint256 size, uint256 totalSize);
    event ReceiveFee(
        address indexed pool,
        address indexed token,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    event SetConfig(address indexed pool, bytes32 key, bytes32 value);
    event CollectFee(
        address indexed pool,
        address indexed token,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    event UpdateMarketBorrowing(
        address indexed pool,
        bytes32 indexed marketId,
        uint256 feeRateApy, // 1e18
        uint256 cumulatedBorrowingPerUsd // 1e18
    );

    function emitAddLiquidity(
        address account,
        address tokenAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    ) external;

    function emitRemoveLiquidity(
        address account,
        address collateralAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    ) external;

    function emitLiquidityBalanceIn(
        address tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    ) external;

    // remove liquidity without burn shares. called by swap
    function emitLiquidityBalanceOut(
        address tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    ) external;

    function emitOpenPosition(bytes32 marketId, uint256 size, uint256 averageEntryPrice, uint256 totalSize) external;

    function emitClosePosition(bytes32 marketId, uint256 size, uint256 totalSize) external;

    function emitReceiveFee(
        address token,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    ) external;

    function emitSetConfig(bytes32 key, bytes32 value) external;

    function emitCollectFee(address token, uint256 tokenPrice, uint256 collateralAmount) external;

    function emitUpdateMarketBorrowing(
        bytes32 marketId,
        uint256 feeRateApy, // 1e18
        uint256 cumulatedBorrowingPerUsd // 1e18
    ) external;

    function emitRebalance(
        address rebalancer,
        address token0,
        address token1,
        uint256 price0, // 1e18
        uint256 price1, // 1e18
        uint256 amount0, // 1e18
        uint256 amount1 // 1e18
    ) external;
}
