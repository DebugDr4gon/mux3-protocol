// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../core/trade/Market.sol";
import "../TestSuit.sol";

contract TestBorrowingFee is TestSuit {
    BorrowingFee bf;
    MockPool poolEth;
    MockPool poolUsd;
    bytes32 marketId = bytes32(uint256(0x1));

    function setup() external {
        bf = new BorrowingFee();
        poolEth = new MockPool();
        poolUsd = new MockPool();

        address[] memory pools = new address[](2);
        pools[0] = address(poolEth);
        pools[1] = address(poolUsd);

        bf.setMarket(marketId, pools);
        bf.setBorringInterval(1 days);
    }

    function test_updateMarketBorrowingFee() external {
        uint256 price = 2000e18;

        // bf.updateMarketBorrowingFee(marketId, price);
    }
}

contract BorrowingFee is Market {
    using LibConfigMap for mapping(bytes32 => bytes32);
    using LibTypeCast for uint256;
    using LibTypeCast for int256;

    uint256 _mockBlockTime;

    function setMarket(bytes32 marketId, address[] memory pools) external {
        for (uint256 i = 0; i < pools.length; i++) {
            _markets[marketId].pools.push(BackedPoolState({ backedPool: pools[i] }));
        }
    }

    function setBorringInterval(uint256 interval) external {
        _configs.setUint256(MC_BORROWING_INTERVAL, interval);
    }

    function setBlockTime(uint256 blockTime) external {
        _mockBlockTime = blockTime;
    }
}

contract MockPool {
    uint256 _borrowingFeeRate;

    function setBorrowingFeeRate(uint256 borrowingFeeRate) external {
        _borrowingFeeRate = borrowingFeeRate;
    }

    function borrowingFeeRateApy() external view returns (uint256) {
        return _borrowingFeeRate;
    }
}
