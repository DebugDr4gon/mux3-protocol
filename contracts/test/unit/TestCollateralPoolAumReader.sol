// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../peripherals/CollateralPoolAumReader.sol";
import "../TestSuit.sol";

contract TestFeeder {
    uint8 _decimals;
    int256 _price;

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 0;
        answer = _price;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 0;
    }

    function setPrice(int256 price) external {
        _price = price;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }
}

contract TestCollateralPoolAumReader is TestSuit {
    function test_getPrice() external {
        TestFeeder feeder = new TestFeeder();

        CollateralPoolAumReader reader = new CollateralPoolAumReader();
        reader.initialize();

        reader.setTokenPriceProvider(address(0x1), address(feeder));
        {
            feeder.setDecimals(18);
            feeder.setPrice(1001e18);
            (uint256 price, uint256 timestamp) = reader.getTokenPrice(address(0x1));
            assertEq(price, 1001e18, "E01");
            assertEq(timestamp, block.timestamp, "E02");
        }
        {
            feeder.setDecimals(6);
            feeder.setPrice(1002e6);
            (uint256 price, ) = reader.getTokenPrice(address(0x1));
            assertEq(price, 1002e18, "E01");
        }
        {
            feeder.setDecimals(8);
            feeder.setPrice(1003e8);
            (uint256 price, ) = reader.getTokenPrice(address(0x1));
            assertEq(price, 1003e18, "E01");
        }
        {
            feeder.setDecimals(27);
            feeder.setPrice(1003e27);
            (uint256 price, ) = reader.getTokenPrice(address(0x1));
            assertEq(price, 1003e18, "E01");
        }
    }
}
