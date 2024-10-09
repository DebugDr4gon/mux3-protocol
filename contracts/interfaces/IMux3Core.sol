// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "../interfaces/ITrade.sol";
import "../interfaces/IManagement.sol";
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
