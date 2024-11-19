// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../core/trade/FacetOpen.sol";
import "../core/trade/FacetClose.sol";
import "../core/trade/FacetPositionAccount.sol";
import "../core/management/FacetManagement.sol";
import "../core/reader/FacetReader.sol";

/**
 * @dev This contract is used to generate typechain types. the real product
 *      uses Diamond proxy pattern and each facet below is one FacetCut.
 */
contract Mux3 is Mux3FacetBase, FacetOpen, FacetClose, FacetPositionAccount, FacetManagement, FacetReader {}
