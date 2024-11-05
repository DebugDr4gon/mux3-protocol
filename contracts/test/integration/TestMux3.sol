// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../core/trade/FacetTrade.sol";
import "../../core/trade/FacetPositionAccount.sol";
import "../../core/management/FacetManagement.sol";
import "../../core/reader/FacetReader.sol";

// Mux3 with a price setter
contract TestMux3 is Mux3FacetBase, FacetTrade, FacetPositionAccount, FacetManagement, FacetReader {
    mapping(bytes32 => uint256) private _mockCache;

    // for withdraw
    receive() external payable {}

    function _priceOf(bytes32 id) internal view override returns (uint256) {
        return _mockCache[id];
    }

    function setMockPrice(bytes32 key, uint256 price) external override {
        _mockCache[key] = price;
    }

    function getInitialLeverage(bytes32 positionId, bytes32 marketId) external view returns (uint256) {
        return _positionAccounts[positionId].positions[marketId].initialLeverage;
    }
}
