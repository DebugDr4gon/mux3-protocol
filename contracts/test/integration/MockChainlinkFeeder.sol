// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

contract MockChainlinkFeeder {
    int256 _price;
    uint256 _timestamp;
    uint8 _decimals;

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setMockData(int256 price, uint256 timestamp) external {
        _price = price;
        _timestamp = timestamp;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _price, _timestamp, _timestamp, 0);
    }
}
