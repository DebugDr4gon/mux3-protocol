// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IErrors {
    // general error
    error ArrayAppendFailed();
    error EssentialConfigNotSet(string key);
    error CapacityExceeded(uint256 capacity, uint256 old, uint256 appending);

    // params
    error InvalidId(bytes32 id);
    error InvalidAmount(uint256 amount);
    error InvalidAddress(address pool);
    error InvalidArrayLength(uint256 a, uint256 b);
    error InvalidPositionSize(uint256 positionSize);
    error InvalidDecimals(uint256 decimals);
    error UnmatchedDecimals(uint256 deicmals, uint256 expectDecimals);

    // price
    error InvalidPriceTimestamp(uint256 timestamp);
    error MissingPrice(bytes32 oracleId);

    // access control
    error NotOwner(bytes32 positionId, address caller, address owner);
    error UnauthorizedRole(bytes32 requiredRole, address caller);
    error UnauthorizedAgent(address account, bytes32 positionId);
    error UnauthorizedCaller(address caller);

    // collateral
    error CollateralAlreadyExists(address tokenAddress);
    error CollateralNotExists(address tokenAddress);
    error CollateralTokenDisabled(address token);

    // market
    error InvalidMarketId(bytes32 marketId);
    error MarketNotExists(bytes32 marketId);
    error MarketAlreadyExists(bytes32 marketId);

    // pool
    error InsufficientLiquidity(
        uint256 requiredLiquidity,
        uint256 liquidityBalance
    );
    error DuplicatedAddress(address pool);
    error PoolAlreadyExist(address pool);
    error PoolNotExists(address pool);
    error CreateProxyFailed();

    // account
    error PositionAccountAlreadyExists(bytes32 positionId);
    error PositionAccountNotExists(bytes32 positionId);
    error UnsafePositionAccount(bytes32 positionId, uint256 safeType);
    error SafePositionAccount(bytes32 positionId, uint256 safeType);
    error InsufficientBalance(uint256 balance, uint256 amount);
    error InitialLeverageOutOfRange(uint256 leverage, uint256 leverageLimit);
    error PositionNotClosed(bytes32 positionId);
}
