// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { LibLogExp } from "../../libraries/LibLogExp.sol";

contract TestLibLogExp {
    function exp(int256 x) public pure returns (int256) {
        return LibLogExp.exp(x);
    }

    function ln(int256 x) public pure returns (int256) {
        return LibLogExp.ln(x);
    }
}
