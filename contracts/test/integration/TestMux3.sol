// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../core/management/FacetManagement.sol";
import "../../core/trade/FacetTrade.sol";
import "../../core/management/FacetManagement.sol";
import "../../core/reader/FacetReader.sol";

contract TestMux3 is FacetTrade, FacetManagement, FacetReader {
    mapping(bytes32 => uint256) private _mockCache;

    function initialize() external initializer {
        __Mux3Store_init(msg.sender);
    }

    function _priceOf(bytes32 id) internal view override returns (uint256) {
        return _mockCache[id];
    }

    function setMockPrice(bytes32 key, uint256 price) external {
        _mockCache[key] = price;
    }
}
