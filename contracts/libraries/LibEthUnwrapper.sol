// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../interfaces/IWETH9.sol";
import "../interfaces/IErrors.sol";

library LibEthUnwrapper {
    uint256 constant DEFAULT_GAS_LIMIT = 50_000;

    /**
     * @dev Unwrap WETH into ETH and send to `to`
     *
     *      assume the current contract has enough WETH balance.
     */
    function unwrap(address weth, address payable to, uint256 rawAmount) internal returns (bool) {
        require(to != address(0), IErrors.InvalidAddress(to));
        if (rawAmount == 0) {
            return false;
        }

        // wrap
        IWETH9(weth).withdraw(rawAmount);

        // send
        bool success;
        // use an assembly call to avoid loading large data into memory
        // input mem[in…(in+insize)]
        // output area mem[out…(out+outsize))]
        assembly {
            success := call(
                DEFAULT_GAS_LIMIT, // gas limit
                to, // receiver
                rawAmount, // value
                0, // in
                0, // insize
                0, // out
                0 // outsize
            )
        }
        if (success) {
            return true;
        }

        // wrap and send WETH
        IWETH9(weth).deposit{ value: rawAmount }();
        IWETH9(weth).transfer(to, rawAmount);
        return false;
    }
}
