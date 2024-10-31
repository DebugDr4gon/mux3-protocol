// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../interfaces/IMux3Core.sol";
import "./OrderBookStore.sol";

struct PriceRawData {
    bytes32 id;
    address provider;
    bytes rawData;
}

contract PriceProvider is OrderBookStore {
    using AddressUpgradeable for address;

    function setPrices(
        PriceRawData[] memory priceData
    ) external onlyRole(BROKER_ROLE) {
        require(priceData.length > 0, "PriceProvider: priceData is empty");
        for (uint256 i = 0; i < priceData.length; i++) {
            IManagement(_storage.mux3Facet).setPrice(
                priceData[i].id,
                priceData[i].provider,
                priceData[i].rawData
            );
        }
    }
}
