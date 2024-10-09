// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IOrderBook.sol";
import "../interfaces/IConstants.sol";
import "../libraries/LibConfigTable.sol";
import "./OrderBookStore.sol";

contract OrderBookGetter is OrderBookStore, IOrderBookGetter {
    using LibConfigTable for ConfigTable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function nextOrderId() external view returns (uint64) {
        return _storage.nextOrderId;
    }

    function sequence() external view returns (uint64) {
        return _storage.sequence;
    }

    function configValue(bytes32 key) external view returns (bytes32) {
        return _configTable.getBytes32(key);
    }

    function _isBroker(address broker) internal view returns (bool) {
        return hasRole(BROKER_ROLE, broker);
    }

    function _isMaintainer(address maintainer) internal view returns (bool) {
        return hasRole(MAINTAINER_ROLE, maintainer);
    }

    function _isDelegator(address delegator) internal view returns (bool) {
        return hasRole(DELEGATOR_ROLE, delegator);
    }

    function _liquidityLockPeriod() internal view returns (uint256 period) {
        period = _configTable.getUint256(MCO_LIQUIDITY_LOCK_PERIOD);
    }

    function isOrderPaused(
        OrderType orderType
    ) internal view returns (bool paused) {
        if (orderType == OrderType.PositionOrder) {
            paused = _configTable.getBoolean(MCO_POSITION_ORDER_PAUSED);
        } else if (orderType == OrderType.LiquidityOrder) {
            paused = _configTable.getBoolean(MCO_LIQUIDITY_ORDER_PAUSED);
        } else if (orderType == OrderType.WithdrawalOrder) {
            paused = _configTable.getBoolean(MCO_WITHDRAWAL_ORDER_PAUSED);
        }
    }

    function marketOrderTimeout() internal view returns (uint256 timeout) {
        timeout = _configTable.getUint256(MCO_MARKET_ORDER_TIMEOUT);
    }

    function maxLimitOrderTimeout() internal view returns (uint256 timeout) {
        timeout = _configTable.getUint256(MCO_LIMIT_ORDER_TIMEOUT);
    }

    function referralManager() internal view returns (address ref) {
        ref = _configTable.getAddress(MCO_REFERRAL_MANAGER);
    }

    function cancelCoolDown() internal view returns (uint256 timeout) {
        timeout = _configTable.getUint256(MCO_CANCEL_COOL_DOWN);
    }

    /**
     * @notice Get an Order by orderId.
     */
    function getOrder(
        uint64 orderId
    ) external view returns (OrderData memory, bool) {
        return (
            _storage.orderData[orderId],
            _storage.orderData[orderId].version > 0
        );
    }

    /**
     * @notice Get Order List for all Traders.
     */
    function getOrders(
        uint256 begin,
        uint256 end
    )
        external
        view
        returns (OrderData[] memory orderDataArray, uint256 totalCount)
    {
        totalCount = _storage.orders.length();
        if (begin >= end || begin >= totalCount) {
            return (orderDataArray, totalCount);
        }
        end = end <= totalCount ? end : totalCount;
        uint256 size = end - begin;
        orderDataArray = new OrderData[](size);
        for (uint256 i = 0; i < size; i++) {
            uint64 orderId = uint64(_storage.orders.at(i + begin));
            orderDataArray[i] = _storage.orderData[orderId];
        }
    }

    /**
     * @notice Get Order List for a User.
     */
    function getOrdersOf(
        address user,
        uint256 begin,
        uint256 end
    )
        external
        view
        returns (OrderData[] memory orderDataArray, uint256 totalCount)
    {
        EnumerableSetUpgradeable.UintSet storage orders = _storage.userOrders[
            user
        ];
        totalCount = orders.length();
        if (begin >= end || begin >= totalCount) {
            return (orderDataArray, totalCount);
        }
        end = end <= totalCount ? end : totalCount;
        uint256 size = end - begin;
        orderDataArray = new OrderData[](size);
        for (uint256 i = 0; i < size; i++) {
            uint64 orderId = uint64(orders.at(i + begin));
            orderDataArray[i] = _storage.orderData[orderId];
        }
    }
}
