// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

contract TestEnumerableSet {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    mapping(uint256 => EnumerableSetUpgradeable.UintSet) _orderIds;

    function add(uint256 orderId) external {
        _orderIds[1234].add(orderId);
    }

    function clear() external {
        _clear(_orderIds[1234]);
    }

    function _clear(EnumerableSetUpgradeable.UintSet storage a) internal {
        for (uint256 len = a.length(); len > 0; len--) {
            a.remove(a.at(len - 1));
        }
    }

    function dump() external view returns (uint256[] memory orderIds) {
        EnumerableSetUpgradeable.UintSet storage ids = _orderIds[1234];
        orderIds = new uint256[](ids.length());
        for (uint256 i = 0; i < ids.length(); i++) {
            orderIds[i] = ids.at(i);
        }
    }

    function contains(uint256 orderId) external view returns (bool) {
        return _orderIds[1234].contains(orderId);
    }
}
