// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./IConstants.sol";

interface ITrade {
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
        uint256 collateralAmount, // token.decimals
        uint256 borrowingFeeUsd // 1e18
    );

    event CreatePositionAccount(
        address indexed owner,
        uint256 index,
        bytes32 indexed positionId
    );

    event SetInitialLeverage(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 marketId,
        uint256 leverage
    );

    event UpdatePositionBorrowingFee(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        uint256 borrowingFeeUsd
    );

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
        bool[] hasProfits,
        uint256[] poolPnlUsds,
        uint256 positionFeeUsd, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts
    );

    event SetPrice(
        bytes32 priceId,
        address provider,
        bytes data,
        uint256 price,
        uint256 timestamp
    );

    function setPrice(
        bytes32 priceId,
        address provider,
        bytes memory oracleCalldata
    ) external;

    function updateBorrowingFee(bytes32 marketId, bytes32 positionId) external;

    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 leverage
    ) external;

    function deposit(
        bytes32 positionId,
        address collateralToken,
        uint256 amount
    ) external;

    function withdraw(
        bytes32 positionId,
        address collateralToken,
        uint256 amount
    ) external;

    function withdrawAll(bytes32 positionId) external;

    function openPosition(
        bytes32 marketId,
        bytes32 positionId,
        uint256 size
    ) external returns (uint256 tradingPrice);

    function closePosition(
        bytes32 marketId,
        bytes32 positionId,
        uint256 size
    ) external returns (uint256 tradingPrice);
}
