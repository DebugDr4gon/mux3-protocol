// SPDX-License-Identifier: GPL-2.0-or-later
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

    function openPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        address lastConsumedToken
    ) external returns (uint256 tradingPrice, uint256 borrowingFeeUsd, uint256 positionFeeUsd);

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
