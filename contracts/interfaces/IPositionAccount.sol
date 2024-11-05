// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

uint256 constant SAFE_INITITAL_MARGIN = 0x1;
uint256 constant SAFE_MAINTENANCE_MARGIN = 0x2;
uint256 constant SAFE_LEVERAGE = 0x3;

struct PositionAccountInfo {
    address owner;
    EnumerableSetUpgradeable.AddressSet activeCollaterals;
    EnumerableSetUpgradeable.Bytes32Set activeMarkets;
    mapping(address => uint256) collaterals; // decimals = 18
    mapping(bytes32 => PositionData) positions; // marketId (implied isLong) => PositionData
}

struct PositionData {
    uint256 initialLeverage;
    uint256 lastIncreasedTime;
    uint256 realizedBorrowingUsd;
    mapping(address => PositionPoolData) pools; // poolId => PositionPoolData
}

struct PositionPoolData {
    uint256 size;
    uint256 entryPrice;
    uint256 entryBorrowing;
}

interface IPositionAccount {
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
