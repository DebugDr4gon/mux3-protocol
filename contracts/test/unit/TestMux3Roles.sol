// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../libraries/LibMux3Roles.sol";

contract TestMux3Roles is Mux3RolesAdmin {
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
