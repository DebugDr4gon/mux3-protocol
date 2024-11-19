// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IErrors {
    // config
    error EssentialConfigNotSet(string key);
    error CapacityExceeded(uint256 capacity, uint256 old, uint256 appending);
    error UnexpectedState(uint256 expected, uint256 actual);

    // params
    error InvalidId(bytes32 id);
    error InvalidAmount(uint256 amount);
    error InvalidAddress(address pool);
    error InvalidArrayLength(uint256 a, uint256 b);
    error InvalidLotSize(uint256 positionSize, uint256 lotSize);
    error InvalidDecimals(uint256 decimals);
    error UnmatchedDecimals(uint256 deicmals, uint256 expectDecimals);
    error InvalidCloseSize(uint256 closingSize, uint256 positionSize);

    // price
    error InvalidPriceTimestamp(uint256 timestamp);
    error MissingPrice(bytes32 oracleId);
    error LimitPriceNotMet(uint256 expected, uint256 actual);

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
    error MarketTradeDisabled(bytes32 marketId);

    // pool
    error InsufficientLiquidity(uint256 requiredLiquidity, uint256 liquidityBalance); // 1e18, 1e18
    error DuplicatedAddress(address pool);
    error PoolAlreadyExist(address pool);
    error PoolNotExists(address pool);
    error CreateProxyFailed();

    // account
    error PositionAccountAlreadyExists(bytes32 positionId);
    error PositionAccountNotExists(bytes32 positionId);
    error UnsafePositionAccount(bytes32 positionId, uint256 safeType);
    error SafePositionAccount(bytes32 positionId, uint256 safeType);
    error InsufficientCollateralBalance(address collateralToken, uint256 balance, uint256 requiredAmount);
    error InsufficientCollateralUsd(uint256 requiredUsd);
    error InitialLeverageOutOfRange(uint256 leverage, uint256 leverageLimit);
    error PositionNotClosed(bytes32 positionId);
    error OnlySingleMarketPositionAllowed(bytes32 positionId);

    // implies bug
    error ArrayAppendFailed();
    error AllocationLengthMismatch(uint256 len1, uint256 len2);
    error AllocationPositionMismatch(uint256 positionSize1, uint256 positionSize2);
    error OutOfBound(uint256 index, uint256 length);
}
