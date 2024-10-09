// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

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
        uint256 collateralAmount // token.decimals
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

    event UpdateBorrowingFee(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        address[] feeAddresses,
        uint256[] feeAmounts
    );

    event OpenPosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        uint256 size,
        uint256[] allocations,
        uint256 tradingPrice,
        uint256 newEntryPrice,
        uint256 newSize,
        address[] positionFeeAddresses,
        uint256[] positionFeeAmounts, // 1e18
        address[] borrowingFeeAddresses,
        uint256[] borrowingFeeAmounts // 1e18
    );

    event ClosePosition(
        address indexed owner,
        bytes32 indexed positionId,
        bytes32 indexed marketId,
        bool isLong,
        uint256 size,
        uint256[] allocations,
        uint256 tradingPrice,
        uint256 newEntryPrice,
        uint256 newSize,
        address[] positionFeeAddresses,
        uint256[] positionFeeAmounts, // 1e18
        address[] borrowingFeeAddresses,
        uint256[] borrowingFeeAmounts // 1e18
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
