// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "./IConstants.sol";

interface IFacetOpen {
    event OpenPosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        uint256 size,
        uint256 tradingPrice,
        address[] backedPools,
        uint256[] allocations, // 1e18
        uint256[] newSizes, // 1e18
        uint256[] newEntryPrices, // 1e18
        uint256 positionFeeUsd, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts // 1e18
    );

    event ReallocatePosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        address fromPool,
        address toPool,
        uint256 size,
        uint256 tradingPrice, // the price for settling between pools
        uint256 fromPoolOldEntryPrice, // previous entry price from the fromPool
        address[] backedPools,
        uint256[] newSizes,
        uint256[] newEntryPrices,
        // reallocation doesn't settle upnl for the PositionAccount.
        // this represents pnL settlement between pools where only the fromPool generates pnl
        int256[] poolPnlUsds,
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts
    );

    struct OpenPositionArgs {
        bytes32 positionId;
        bytes32 marketId;
        uint256 size;
        address lastConsumedToken;
        bool isUnwrapWeth;
    }

    struct OpenPositionResult {
        uint256 tradingPrice;
        uint256 borrowingFeeUsd;
        uint256 positionFeeUsd;
    }

    struct ReallocatePositionArgs {
        bytes32 positionId;
        bytes32 marketId;
        address fromPool;
        address toPool;
        uint256 size;
        address lastConsumedToken;
        bool isUnwrapWeth;
    }

    struct ReallocatePositionResult {
        uint256 tradingPrice;
        uint256 borrowingFeeUsd;
        // note: reallocate does not settle upnl for this PositionAccount
    }

    function openPosition(OpenPositionArgs memory args) external returns (OpenPositionResult memory result);

    function reallocatePosition(
        ReallocatePositionArgs memory args
    ) external returns (ReallocatePositionResult memory result);
}

interface IFacetClose {
    event ClosePosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        uint256 size, // closing
        uint256 tradingPrice,
        address[] backedPools,
        uint256[] allocations, // 1e18
        uint256[] newSizes, // 1e18
        uint256[] newEntryPrices, // 1e18
        int256[] poolPnlUsds, // 1e18
        uint256 positionFeeUsd, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts // 1e18
    );

    event LiquidatePosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        uint256 size, // size before liquidate = liquidate size
        uint256 tradingPrice, // 1e18
        address[] backedPools,
        uint256[] allocations, // 1e18
        int256[] poolPnlUsds, // 1e18
        uint256 positionFeeUsd, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts // 1e18
    );

    struct ClosePositionArgs {
        bytes32 positionId;
        bytes32 marketId;
        uint256 size;
        address lastConsumedToken;
        bool isUnwrapWeth;
    }

    struct ClosePositionResult {
        uint256 tradingPrice;
        int256[] poolPnlUsds;
        uint256 borrowingFeeUsd;
        uint256 positionFeeUsd;
    }

    function closePosition(ClosePositionArgs memory args) external returns (ClosePositionResult memory result);

    struct LiquidateArgs {
        bytes32 positionId;
        address lastConsumedToken;
        bool isUnwrapWeth;
    }

    struct LiquidatePositionResult {
        bytes32 marketId;
        uint256 tradingPrice;
        int256[] poolPnlUsds;
        uint256 borrowingFeeUsd;
        uint256 positionFeeUsd;
    }

    struct LiquidateResult {
        LiquidatePositionResult[] positions;
    }

    function liquidate(LiquidateArgs memory args) external returns (LiquidateResult memory result);
}

interface IFacetPositionAccount {
    event Deposit(
        address indexed owner,
        bytes32 indexed positionId,
        address collateralToken,
        uint256 collateralAmount // token.decimals
    );

    event Withdraw(
        address indexed owner,
        bytes32 indexed positionId,
        address collateralToken,
        uint256 collateralWad, // 1e18
        address withdrawToken, // if swap, this is the tokeOut. if not swap, this is the collateralToken
        uint256 withdrawAmount // token.decimals
    );

    event DepositWithdrawFinish(
        address indexed owner,
        bytes32 indexed positionId,
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts
    );

    event CreatePositionAccount(address indexed owner, uint256 index, bytes32 indexed positionId);

    event SetInitialLeverage(address indexed owner, bytes32 indexed positionId, bytes32 marketId, uint256 leverage);

    event UpdatePositionBorrowingFee(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        uint256 borrowingFeeUsd
    );

    function setInitialLeverage(bytes32 positionId, bytes32 marketId, uint256 leverage) external;

    function deposit(bytes32 positionId, address collateralToken, uint256 amount) external;

    struct WithdrawArgs {
        bytes32 positionId;
        address collateralToken;
        uint256 amount;
        address lastConsumedToken;
        bool isUnwrapWeth;
        address withdrawSwapToken;
        uint256 withdrawSwapSlippage;
    }

    function withdraw(WithdrawArgs memory args) external;

    struct WithdrawAllArgs {
        bytes32 positionId;
        bool isUnwrapWeth;
        address withdrawSwapToken;
        uint256 withdrawSwapSlippage;
    }

    function withdrawAll(WithdrawAllArgs memory args) external;

    struct WithdrawUsdArgs {
        bytes32 positionId;
        uint256 collateralUsd; // 1e18
        address lastConsumedToken;
        bool isUnwrapWeth;
        address withdrawSwapToken;
        uint256 withdrawSwapSlippage;
    }

    function withdrawUsd(WithdrawUsdArgs memory args) external;

    function updateBorrowingFee(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken,
        bool isUnwrapWeth
    ) external;
}
