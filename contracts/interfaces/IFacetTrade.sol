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
        uint256[] allocations,
        uint256[] newSizes,
        uint256[] newEntryPrices,
        uint256 positionFeeUsd, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts
    );

    event ReallocatePosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        address fromPool,
        address toPool,
        uint256 size,
        uint256 tradingPrice,
        address[] backedPools,
        uint256[] newSizes,
        uint256[] newEntryPrices,
        int256[] poolPnlUsds, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts
    );

    function openPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        address lastConsumedToken
    ) external returns (uint256 tradingPrice, uint256 borrowingFeeUsd, uint256 positionFeeUsd);

    struct ReallocatePositionArgs {
        bytes32 positionId;
        bytes32 marketId;
        address fromPool;
        address toPool;
        uint256 size;
        address lastConsumedToken;
    }

    struct ReallocatePositionResult {
        uint256 tradingPrice;
        int256[] poolPnlUsds;
        uint256 borrowingFeeUsd;
    }

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
        uint256 size,
        uint256 tradingPrice,
        address[] backedPools,
        uint256[] allocations,
        uint256[] newSizes,
        uint256[] newEntryPrices,
        int256[] poolPnlUsds, // 1e18
        uint256 positionFeeUsd, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts
    );

    event LiquidatePosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        uint256 oldSize,
        uint256 tradingPrice,
        address[] backedPools,
        uint256[] allocations,
        int256[] poolPnlUsds, // 1e18
        uint256 positionFeeUsd, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts
    );

    function closePosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        address lastConsumedToken
    )
        external
        returns (uint256 tradingPrice, int256[] memory poolPnlUsds, uint256 borrowingFeeUsd, uint256 positionFeeUsd);

    function liquidatePosition(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken
    )
        external
        returns (uint256 tradingPrice, int256[] memory poolPnlUsds, uint256 borrowingFeeUsd, uint256 positionFeeUsd);
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

    function withdraw(
        bytes32 positionId,
        address collateralToken,
        uint256 amount,
        address lastConsumedToken,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external;

    function withdrawAll(
        bytes32 positionId,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external;

    function withdrawUsd(
        bytes32 positionId,
        uint256 collateralUsd, // 1e18
        address lastConsumedToken,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external;

    function updateBorrowingFee(bytes32 positionId, bytes32 marketId, address lastConsumedToken) external;
}
