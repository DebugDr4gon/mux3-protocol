// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

interface IWETH9 {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}
