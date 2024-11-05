// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import { StringsUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

/**
 * a simplified AccessControlEnumerableUpgradeable that does not implement ERC165.
 * this is the store part that does not have any external functions.
 */
contract Mux3RolesStore is Initializable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    mapping(bytes32 => EnumerableSetUpgradeable.AddressSet) internal _roleMembers;
    uint256[50] private __gap;

    modifier onlyRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function _hasRole(bytes32 role, address account) internal view returns (bool) {
        return _roleMembers[role].contains(account);
    }

    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!_hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        StringsUpgradeable.toHexString(account),
                        " is missing role ",
                        StringsUpgradeable.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }

    function _grantRole(bytes32 role, address account) internal virtual {
        if (!_hasRole(role, account)) {
            _roleMembers[role].add(account);
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal virtual {
        if (_hasRole(role, account)) {
            _roleMembers[role].remove(account);
            emit RoleRevoked(role, account, msg.sender);
        }
    }
}

/**
 * a simplified AccessControlEnumerableUpgradeable that does not implement ERC165.
 * this is the external part that only contains management functions.
 */
contract Mux3RolesAdmin is Mux3RolesStore {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function __LibMux3Roles_init_unchained() internal onlyInitializing {}

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _hasRole(role, account);
    }

    function getRoleMemberCount(bytes32 role) external view returns (uint256) {
        return _roleMembers[role].length();
    }

    function getRoleMember(bytes32 role, uint256 index) external view returns (address) {
        return _roleMembers[role].at(index);
    }
}
