// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface ICallbackRegister {
    function isCallbackRegistered(address callback) external view returns (bool);
}
