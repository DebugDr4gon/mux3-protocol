// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../interfaces/IBorrowingRate.sol";

struct MarketState {
    bool isLong;
    uint256 totalSize;
    uint256 averageEntryPrice;
    uint256 cumulatedBorrowingPerUsd; // $borrowingFee / $positionValue, always increasing
    uint256 lastBorrowingUpdateTime;
}

interface ICollateralPool {
    // add liquidity, mint shares
    event AddLiquidity(
        address indexed account,
        address indexed tokenAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    );
    // burn shares, remove liquidity
    event RemoveLiquidity(
        address indexed account,
        address indexed collateralAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    );
    // add liquidity without mint shares. called by fees, loss, swap
    event LiquidityBalanceIn(
        address tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    // remove liquidity without burn shares. called by swap
    event LiquidityBalanceOut(
        address tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    event OpenPosition(
        bytes32 marketId,
        uint256 size,
        uint256 averageEntryPrice,
        uint256 totalSize
    );
    event ClosePosition(bytes32 marketId, uint256 size, uint256 totalSize);
    event ReceiveFee(
        address token,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    event SetConfig(bytes32 key, bytes32 value);
    event CollectFee(
        address token,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    );
    event UpdateMarketBorrowing(
        bytes32 marketId,
        uint256 feeRateApy, // 1e18
        uint256 cumulatedBorrowingPerUsd // 1e18
    );

    function setConfig(bytes32 key, bytes32 value) external;

    function configValue(bytes32 key) external view returns (bytes32);

    function collateralToken() external view returns (address);

    function borrowingFeeRateApy(
        bytes32 marketId
    ) external view returns (uint256 feeRateApy);

    function markets() external view returns (bytes32[] memory);

    function marketState(
        bytes32 marketId
    ) external view returns (MarketState memory);

    function marketStates()
        external
        view
        returns (bytes32[] memory marketIds, MarketState[] memory states);

    function setMarket(bytes32 marketId, bool isLong) external;

    function openPosition(bytes32 marketId, uint256 size) external;

    function closePosition(
        bytes32 marketId,
        uint256 size,
        uint256 entryPrice
    ) external;

    function realizeProfit(
        uint256 pnlUsd
    ) external returns (address token, uint256 wad);

    function realizeLoss(address token, uint256 rawAmount) external;

    function addLiquidity(
        address account,
        uint256 collaterals
    ) external returns (uint256 shares);

    function removeLiquidity(
        address account,
        uint256 shares
    ) external returns (uint256 collateralAmount);

    function receiveFee(
        address token,
        uint256 rawAmount // token.decimals
    ) external;

    function updateMarketBorrowing(
        bytes32 marketId
    ) external returns (uint256 newCumulatedBorrowingPerUsd);

    function makeBorrowingContext(
        bytes32 marketId
    ) external view returns (IBorrowingRate.AllocatePool memory);

    function positionPnl(
        bytes32 marketId,
        uint256 size,
        uint256 entryPrice,
        uint256 marketPrice
    ) external view returns (bool hasProfit, uint256 cappedPnlUsd);
}
