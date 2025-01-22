// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../interfaces/ICallbackRegister.sol";

contract MockCallbackRegister is ICallbackRegister {
    mapping(address => bool) private _whitelist;

    function register(address account, bool isWhitelisted) external {
        _whitelist[account] = isWhitelisted;
    }

    function isCallbackRegistered(address callback) external view returns (bool) {
        return _whitelist[callback];
    }
}
