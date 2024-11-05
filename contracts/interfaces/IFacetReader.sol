// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../interfaces/IPositionAccount.sol";
import "../interfaces/IMarket.sol";

struct AccountReader {
    bytes32 positionId;
    CollateralReader[] collaterals;
    PositionReader[] positions;
}

struct CollateralReader {
    address collateralAddress;
    uint256 collateralAmount;
}

struct PositionReader {
    bytes32 marketId;
    uint256 initialLeverage;
    uint256 lastIncreasedTime;
    uint256 realizedBorrowingUsd;
    PositionPoolReader[] pools;
}

struct PositionPoolReader {
    address poolAddress;
    uint256 size;
    uint256 entryPrice;
    uint256 entryBorrowing;
}

interface IFacetReader {
    function priceOf(address token) external view returns (uint256);

    function priceOf(bytes32 id) external view returns (uint256);

    function configValue(bytes32 key) external view returns (bytes32);

    function marketConfigValue(bytes32 marketId, bytes32 key) external view returns (bytes32);

    function marketState(bytes32 marketId) external view returns (string memory symbol, bool isLong);

    function getCollateralToken(address token) external view returns (bool enabled, uint8 decimals);

    function listCollateralTokens() external view returns (address[] memory);

    function getCollateralPool(address pool) external view returns (bool enabled);

    function listCollateralPool() external view returns (address[] memory);

    function listMarkets() external view returns (bytes32[] memory);

    function listMarketPools(bytes32 marketId) external view returns (BackedPoolState[] memory);

    function listPositionIdsOf(address trader) external view returns (bytes32[] memory);

    function listAccountCollaterals(bytes32 positionId) external view returns (CollateralReader[] memory collaterals);

    function listAccountPositions(bytes32 positionId) external view returns (PositionReader[] memory positions);

    function listAccountCollateralsAndPositionsOf(
        address trader
    ) external view returns (AccountReader[] memory positions);

    function getPositionAccount(
        bytes32 positionId,
        bytes32 marketId
    ) external view returns (PositionReader memory position);
}
