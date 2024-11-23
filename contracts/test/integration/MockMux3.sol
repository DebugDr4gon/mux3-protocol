// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../interfaces/IFacetTrade.sol";
import "../../core/Mux3FacetBase.sol";
import "../../core/management/FacetManagement.sol";
import "../../core/reader/FacetReader.sol";

// TestMux3 without FacetTrade, FacetPositionAccount
contract MockMux3 is FacetManagement, FacetReader, IFacetOpen, IFacetClose, IFacetPositionAccount {
    mapping(bytes32 => uint256) private _mockCache;

    // for withdraw
    receive() external payable {}

    function setInitialLeverage(bytes32 positionId, bytes32 marketId, uint256 leverage) external {}

    function deposit(bytes32 positionId, address collateralToken, uint256 amount) external {}

    function withdraw(WithdrawArgs memory args) external {}

    function withdrawAll(WithdrawAllArgs memory args) external {}

    function withdrawUsd(WithdrawUsdArgs memory args) external {}

    function updateBorrowingFee(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken,
        bool isUnwrapWeth
    ) external {}

    function openPosition(OpenPositionArgs memory args) external returns (OpenPositionResult memory result) {}

    function closePosition(ClosePositionArgs memory args) external returns (ClosePositionResult memory result) {}

    function liquidatePosition(
        LiquidatePositionArgs memory args
    ) external returns (LiquidatePositionResult memory result) {}

    function _priceOf(bytes32 id) internal view virtual override returns (uint256) {
        return _mockCache[id];
    }

    function setMockPrice(bytes32 key, uint256 price) external {
        _mockCache[key] = price;
    }

    function setPrice(bytes32 key, address, bytes memory oralceCalldata) external override {
        uint256 price = abi.decode(oralceCalldata, (uint256));
        _mockCache[key] = price;
    }

    function setCachedPrices(bytes32[] memory ids, uint256[] memory prices) external {}
}
