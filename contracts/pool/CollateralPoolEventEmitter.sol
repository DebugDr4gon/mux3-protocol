// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IFacetReader.sol";
import "../interfaces/ICollateralPool.sol";
import "../interfaces/ICollateralPoolEventEmitter.sol";

contract CollateralPoolEventEmitter is Initializable, ICollateralPoolEventEmitter {
    address public core;

    function initialize(address _core) external initializer {
        require(_core != address(0), "InvalidAddress");
        core = _core;
    }

    modifier onlyCollateralPool() {
        require(IFacetReader(core).getCollateralPool(msg.sender), "InvalidCaller");
        _;
    }

    function emitAddLiquidity(
        address account,
        address tokenAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    ) external onlyCollateralPool {
        emit AddLiquidity(
            msg.sender,
            account,
            tokenAddress,
            tokenPrice, // 1e18
            feeCollateral, // 1e18
            lpPrice,
            shares
        );
    }

    function emitRemoveLiquidity(
        address account,
        address collateralAddress,
        uint256 tokenPrice, // 1e18
        uint256 feeCollateral, // 1e18
        uint256 lpPrice,
        uint256 shares
    ) external onlyCollateralPool {
        emit RemoveLiquidity(
            msg.sender,
            account,
            collateralAddress,
            tokenPrice, // 1e18
            feeCollateral, // 1e18
            lpPrice,
            shares
        );
    }

    function emitLiquidityBalanceIn(
        address tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    ) external onlyCollateralPool {
        emit LiquidityBalanceIn(
            msg.sender,
            tokenAddress,
            tokenPrice,
            collateralAmount // 1e18
        );
    }

    // remove liquidity without burn shares. called by swap
    function emitLiquidityBalanceOut(
        address tokenAddress,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    ) external onlyCollateralPool {
        emit LiquidityBalanceOut(
            msg.sender,
            tokenAddress,
            tokenPrice,
            collateralAmount // 1e18
        );
    }

    function emitOpenPosition(
        bytes32 marketId,
        uint256 size,
        uint256 averageEntryPrice,
        uint256 totalSize
    ) external onlyCollateralPool {
        emit OpenPosition(msg.sender, marketId, size, averageEntryPrice, totalSize);
    }

    function emitClosePosition(bytes32 marketId, uint256 size, uint256 totalSize) external onlyCollateralPool {
        emit ClosePosition(msg.sender, marketId, size, totalSize);
    }

    function emitReceiveFee(
        address token,
        uint256 tokenPrice,
        uint256 collateralAmount // 1e18
    ) external onlyCollateralPool {
        emit ReceiveFee(
            msg.sender,
            token,
            tokenPrice,
            collateralAmount // 1e18
        );
    }

    function emitSetConfig(bytes32 key, bytes32 value) external onlyCollateralPool {
        emit SetConfig(msg.sender, key, value);
    }

    function emitCollectFee(address token, uint256 tokenPrice, uint256 collateralAmount) external onlyCollateralPool {
        emit CollectFee(
            msg.sender,
            token,
            tokenPrice,
            collateralAmount // 1e18
        );
    }

    function emitUpdateMarketBorrowing(
        bytes32 marketId,
        uint256 feeRateApy, // 1e18
        uint256 cumulatedBorrowingPerUsd // 1e18
    ) external onlyCollateralPool {
        emit UpdateMarketBorrowing(
            msg.sender,
            marketId,
            feeRateApy, // 1e18
            cumulatedBorrowingPerUsd // 1e18
        );
    }

    function emitRebalance(
        address rebalancer,
        address token0,
        address token1,
        uint256 price0, // 1e18
        uint256 price1, // 1e18
        uint256 amount0, // 1e18
        uint256 amount1 // 1e18
    ) external onlyCollateralPool {
        emit Rebalance(msg.sender, rebalancer, token0, token1, price0, price1, amount0, amount1);
    }
}
