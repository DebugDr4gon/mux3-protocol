// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./IConstants.sol";

interface ITrade {
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

    event LiquidatePosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        uint256 oldSize,
        uint256 tradingPrice,
        address[] backedPools,
        uint256[] allocations,
        bool[] hasProfits,
        uint256[] poolPnlUsds,
        uint256 positionFeeUsd, // 1e18
        uint256 borrowingFeeUsd, // 1e18
        address[] newCollateralTokens,
        uint256[] newCollateralAmounts
    );

    function openPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) external returns (uint256 tradingPrice);

    function closePosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) external returns (uint256 tradingPrice);

    function liquidatePosition(
        bytes32 positionId,
        bytes32 marketId
    ) external returns (uint256 tradingPrice);
}
