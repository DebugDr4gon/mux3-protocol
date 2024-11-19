// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../interfaces/IFacetTrade.sol";
import "../interfaces/IFacetManagement.sol";
import "../interfaces/IFacetReader.sol";

enum Enabled {
    Invalid,
    Enabled,
    Disabled
}

struct CollateralTokenInfo {
    Enabled enabled;
    uint8 decimals;
}
