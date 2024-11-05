// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract Rescue {
    function rescueETH() public payable {
        require(msg.sender == 0x44cBfc3Ce762fC0Fee9Ddd6372804b7B660176bC, "OWN");
        Address.sendValue(payable(msg.sender), address(this).balance);
    }

    function rescueERC20(address token) public {
        require(msg.sender == 0x44cBfc3Ce762fC0Fee9Ddd6372804b7B660176bC, "OWN");
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }
}
