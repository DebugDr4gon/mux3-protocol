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

    function withdraw(
        bytes32 positionId,
        address collateralToken,
        uint256 rawAmount, // token.decimals
        address lastConsumedToken,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external {}

    function withdrawAll(
        bytes32 positionId,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external {}

    function withdrawUsd(
        bytes32 positionId,
        uint256 collateralUsd, // 1e18
        address lastConsumedToken,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external {}

    function updateBorrowingFee(bytes32 positionId, bytes32 marketId, address lastConsumedToken) external {}

    function openPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        address lastConsumedToken
    ) external returns (uint256 tradingPrice, uint256 borrowingFeeUsd, uint256 positionFeeUsd) {}

    function closePosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size,
        address lastConsumedToken
    )
        external
        returns (uint256 tradingPrice, int256[] memory poolPnlUsds, uint256 borrowingFeeUsd, uint256 positionFeeUsd)
    {}

    function liquidatePosition(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken
    )
        external
        returns (uint256 tradingPrice, int256[] memory poolPnlUsds, uint256 borrowingFeeUsd, uint256 positionFeeUsd)
    {}

    function reallocatePosition(
        ReallocatePositionArgs memory args
    ) external returns (ReallocatePositionResult memory result) {}

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
