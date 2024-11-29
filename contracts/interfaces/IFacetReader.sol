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
    /**
     * @dev Get price of a token
     */
    function priceOf(address token) external view returns (uint256 price);

    /**
     * @dev Get price of an OracleId
     */
    function priceOf(bytes32 oracleId) external view returns (uint256 price);

    /**
     * @dev Get core global config
     */
    function configValue(bytes32 key) external view returns (bytes32 value);

    /**
     * @dev Get Market config
     */
    function marketConfigValue(bytes32 marketId, bytes32 key) external view returns (bytes32 value);

    /**
     * @dev Get Market state
     */
    function marketState(bytes32 marketId) external view returns (string memory symbol, bool isLong);

    /**
     * @dev Get Collateral config
     */
    function getCollateralToken(address token) external view returns (bool isExist, uint8 decimals);

    /**
     * @dev List collateral tokens
     */
    function listCollateralTokens() external view returns (address[] memory tokens);

    /**
     * @dev Get CollateralPool config
     */
    function getCollateralPool(address pool) external view returns (bool isExist);

    /**
     * @dev List CollateralPool addresses
     */
    function listCollateralPool() external view returns (address[] memory pools);

    /**
     * @dev List Markets
     */
    function listMarkets() external view returns (bytes32[] memory marketIds);

    /**
     * @dev List backed CollateralPool in a Market
     */
    function listMarketPools(bytes32 marketId) external view returns (BackedPoolState[] memory pools);

    /**
     * @dev List PositionIds of a Trader
     */
    function listPositionIdsOf(address trader) external view returns (bytes32[] memory positionIds);

    /**
     * @dev List active PositionIds
     *
     *      "active" means positionId that likely has positions. positionId with only collateral may not be in this list
     */
    function listActivePositionIds(
        uint256 begin,
        uint256 end
    ) external view returns (bytes32[] memory positionIds, uint256 totalLength);

    /**
     * @dev Get Position of (positionId, marketId)
     */
    function getPositionAccount(
        bytes32 positionId,
        bytes32 marketId
    ) external view returns (PositionReader memory position);

    /**
     * @dev List Collaterals of a PositionAccount
     */
    function listAccountCollaterals(bytes32 positionId) external view returns (CollateralReader[] memory collaterals);

    /**
     * @dev List Positions of a PositionAccount
     */
    function listAccountPositions(bytes32 positionId) external view returns (PositionReader[] memory positions);

    /**
     * @dev List Collaterals and Positions of all PositionAccounts of a Trader
     */
    function listCollateralsAndPositionsOf(address trader) external view returns (AccountReader[] memory positions);

    /**
     * @dev List active Collaterals and Positions
     *
     *      "active" means positionId that likely has positions. positionId with only collateral may not be in this list
     */
    function listActiveCollateralsAndPositions(
        uint256 begin,
        uint256 end
    ) external view returns (AccountReader[] memory positions, uint256 totalLength);

    /**
     * @dev Check if deleverage is allowed
     *
     *      note: you should multicall([
     *              updateBorrowingFee,
     *              isDeleverageAllowed
     *            ])
     */
    function isDeleverageAllowed(bytes32 positionId, bytes32 marketId) external view returns (bool);
}
