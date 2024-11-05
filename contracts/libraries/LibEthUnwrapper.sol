// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../interfaces/IWETH9.sol";

library LibEthUnwrapper {
    uint256 constant DEFAULT_GAS_LIMIT = 50_000;

    /**
     * @dev unwrap WETH into ETH and send to `to`
     *
     *      assume the current contract has enough WETH balance.
     */
    function unwrap(address weth, address payable to, uint256 rawAmount) internal {
        require(to != address(0), "Zero receiver");
        if (rawAmount == 0) {
            return;
        }

        // wrap
        IWETH9(weth).withdraw(rawAmount);

        // send
        (bool success, ) = to.call{ value: rawAmount, gas: DEFAULT_GAS_LIMIT }("");
        if (success) {
            return;
        }

        // wrap and send WETH
        IWETH9(weth).deposit{ value: rawAmount }();
        IWETH9(weth).transfer(to, rawAmount);
    }
}
