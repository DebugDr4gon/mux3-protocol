// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

interface IPriceProvider {
    function getOraclePrice(
        bytes32 priceId,
        bytes memory data
    ) external returns (uint256, uint256);
}
