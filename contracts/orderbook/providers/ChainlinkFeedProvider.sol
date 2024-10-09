// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

contract ChainlinkFeedProvider is Ownable {
    uint256 public priceExpiration;
    mapping(address => bool) public feeders;

    event SetPriceExpiration(uint256 priceExpiration);
    event SetValidFeeder(address feeder, bool isValid);

    error InvalidFeederAddress();
    error InvalidFeeder();
    error InvalidPriceExpiration(uint256 expiration);
    error InvalidPrice(int256 price);
    error PriceExpired(uint256 timestamp, uint256 blockTimestamp);

    function setValidFeeder(address feeder, bool isValid) external onlyOwner {
        require(feeder != address(0), "Invalid feeder");
        feeders[feeder] = isValid;
        emit SetValidFeeder(feeder, isValid);
    }

    function setPriceExpirationSeconds(
        uint256 _priceExpiration
    ) external onlyOwner {
        require(
            _priceExpiration <= 86400 && _priceExpiration > 30,
            InvalidPriceExpiration(_priceExpiration)
        );
        priceExpiration = _priceExpiration;
        emit SetPriceExpiration(_priceExpiration);
    }

    function getOraclePrice(
        bytes memory rawData
    ) external view returns (uint256, uint256) {
        address _feeder = abi.decode(rawData, (address));
        require(_feeder != address(0), InvalidFeederAddress());
        require(feeders[_feeder], InvalidFeeder());

        AggregatorV2V3Interface feeder = AggregatorV2V3Interface(_feeder);
        uint8 decimals = feeder.decimals();
        (, int256 _price, , uint256 timestamp, ) = feeder.latestRoundData();
        require(
            timestamp + priceExpiration >= block.timestamp,
            PriceExpired(timestamp, block.timestamp)
        );
        require(_price > 0, InvalidPrice(_price));
        uint256 price = uint256(_price) * (10 ** (18 - decimals)); // decimals => 18
        return (price, timestamp);
    }
}
