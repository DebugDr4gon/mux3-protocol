// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../interfaces/ITrade.sol";
import "../../core/Mux3FacetBase.sol";
import "../../core/management/FacetManagement.sol";
import "../../core/reader/FacetReader.sol";

// TestMux3 without FacetTrade, FacetPositionAccount
contract MockMux3 is FacetManagement, FacetReader, ITrade {
    mapping(bytes32 => uint256) private _mockCache;

    function updateBorrowingFee(
        bytes32 positionId,
        bytes32 marketId
    ) external {}

    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 leverage
    ) external {}

    function deposit(
        bytes32 positionId,
        address collateralToken,
        uint256 amount
    ) external {}

    function withdraw(
        bytes32 positionId,
        address collateralToken,
        uint256 amount
    ) external {}

    function withdrawAll(bytes32 positionId) external {}

    function openPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) external returns (uint256 tradingPrice) {}

    function closePosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) external returns (uint256 tradingPrice) {}

    function liquidatePosition(
        bytes32 positionId,
        bytes32 marketId
    ) external returns (uint256 tradingPrice) {}

    function _priceOf(
        bytes32 id
    ) internal view virtual override returns (uint256) {
        return _mockCache[id];
    }

    function setMockPrice(bytes32 key, uint256 price) external override {
        _mockCache[key] = price;
    }

    function setPrice(
        bytes32 key,
        address,
        bytes memory oralceCalldata
    ) external override {
        uint256 price = abi.decode(oralceCalldata, (uint256));
        _mockCache[key] = price;
    }

    function setCachedPrices(
        bytes32[] memory ids,
        uint256[] memory prices
    ) external {}
}
