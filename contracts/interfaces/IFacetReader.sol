// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "../interfaces/IPositionAccount.sol";
import "../interfaces/IMarket.sol";

struct AccountCollateralsAndPositions {
    bytes32 positionId;
    address[] collateralAddresses;
    uint256[] collateralAmounts;
    bytes32[] marketIds;
    PositionData[] positions;
}

interface IFacetReader {
    function priceOf(address token) external view returns (uint256);

    function priceOf(bytes32 id) external view returns (uint256);

    function configValue(bytes32 key) external view returns (bytes32);

    function marketConfigValue(
        bytes32 marketId,
        bytes32 key
    ) external view returns (bytes32);

    function marketState(
        bytes32 marketId
    )
        external
        view
        returns (
            string memory symbol,
            bool isLong,
            uint256 cumulatedBorrowingPerUsd,
            uint256 lastBorrowingFeeUpdateTime
        );

    function getCollateralToken(
        address token
    ) external view returns (bool enabled, uint8 decimals);

    function getCollateralPool(
        address pool
    ) external view returns (bool enabled);

    function listCollateralPool() external view returns (address[] memory);

    function listMarketPools(
        bytes32 marketId
    ) external view returns (BackedPoolState[] memory);

    function listAccountCollaterals(
        bytes32 positionId
    )
        external
        view
        returns (address[] memory tokenAddresses, uint256[] memory balances);

    function listAccountPositions(
        bytes32 positionId
    )
        external
        view
        returns (bytes32[] memory marketIds, PositionData[] memory positions);

    function listAccountCollateralsAndPositionsOf(
        address trader
    ) external view returns (AccountCollateralsAndPositions[] memory positions);
}
