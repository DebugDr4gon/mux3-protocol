// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../core/trade/FacetTrade.sol";
import "../core/trade/FacetPositionAccount.sol";
import "../core/management/FacetManagement.sol";
import "../core/reader/FacetReader.sol";

/**
 * @dev this contract is used to generate typechain types. the real product
 *      uses Diamond proxy pattern and each facet below is one FacetCut.
 */
contract Mux3 is
    Mux3FacetBase,
    FacetTrade,
    FacetPositionAccount,
    FacetManagement,
    FacetReader
{}
