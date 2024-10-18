// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../core/management/FacetManagement.sol";
import "../core/trade/FacetTrade.sol";
import "../core/reader/FacetReader.sol";

contract Mux3 is Mux3FacetBase, FacetTrade, FacetManagement, FacetReader {
    function initialize() external initializer {
        __Mux3Store_init(msg.sender);
    }

    // TODO: remove me if oracleProvider is ready
    function setMockPrice(bytes32 key, uint256 price) external {
        _setCachedPrice(key, price);
    }
}
