// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IOrderBook.sol";
import "../interfaces/IConstants.sol";
import "../libraries/LibConfigMap.sol";
import "./OrderBookStore.sol";

contract OrderBookGetter is OrderBookStore, IOrderBookGetter {
    using LibConfigMap for mapping(bytes32 => bytes32);
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function nextOrderId() external view override returns (uint64) {
        return _storage.nextOrderId;
    }

    function sequence() external view override returns (uint64) {
        return _storage.sequence;
    }

    function configValue(bytes32 key) external view override returns (bytes32) {
        return _storage.configTable.getBytes32(key);
    }

    function gasBalanceOf(address user) external view returns (uint256) {
        return _storage.gasBalances[user];
    }

    /**
     * @notice Get an Order by orderId
     */
    function getOrder(uint64 orderId) external view override returns (OrderData memory, bool) {
        return (_storage.orderData[orderId], _storage.orderData[orderId].version > 0);
    }

    /**
     * @notice Get Order List for all Traders
     */
    function getOrders(
        uint256 begin,
        uint256 end
    ) external view override returns (OrderData[] memory orderDataArray, uint256 totalCount) {
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
     * @notice Get Order List for a User
     */
    function getOrdersOf(
        address user,
        uint256 begin,
        uint256 end
    ) external view override returns (OrderData[] memory orderDataArray, uint256 totalCount) {
        EnumerableSetUpgradeable.UintSet storage orders = _storage.userOrders[user];
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

    /**
     * @notice Get tp/sl orders of a position + marketId
     */
    function getTpslOrders(bytes32 positionId, bytes32 marketId) external view returns (uint64[] memory orderIds) {
        EnumerableSetUpgradeable.UintSet storage ids = _storage.tpslOrders[positionId][marketId];
        orderIds = new uint64[](ids.length());
        for (uint256 i = 0; i < ids.length(); i++) {
            orderIds[i] = LibTypeCast.toUint64(ids.at(i));
        }
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

    function _isOrderPaused(OrderType orderType) internal view returns (bool paused) {
        if (orderType == OrderType.PositionOrder) {
            paused = _storage.configTable.getBoolean(MCO_POSITION_ORDER_PAUSED);
        } else if (orderType == OrderType.LiquidityOrder) {
            paused = _storage.configTable.getBoolean(MCO_LIQUIDITY_ORDER_PAUSED);
        } else if (orderType == OrderType.WithdrawalOrder) {
            paused = _storage.configTable.getBoolean(MCO_WITHDRAWAL_ORDER_PAUSED);
        } else if (orderType == OrderType.RebalanceOrder) {
            paused = _storage.configTable.getBoolean(MCO_REBALANCE_ORDER_PAUSED);
        } else if (orderType == OrderType.AdlOrder) {
            paused = _storage.configTable.getBoolean(MCO_ADL_ORDER_PAUSED);
        } else if (orderType == OrderType.LiquidateOrder) {
            paused = _storage.configTable.getBoolean(MCO_LIQUIDATE_ORDER_PAUSED);
        }
    }

    function _referralManager() internal view returns (address ref) {
        ref = _storage.configTable.getAddress(MCO_REFERRAL_MANAGER);
        // 0 is valid
    }

    function _cancelCoolDown() internal view returns (uint256 timeout) {
        timeout = _storage.configTable.getUint256(MCO_CANCEL_COOL_DOWN);
        // 0 is valid
    }

    function _orderGasFeeGwei() internal view returns (uint256 gasFee) {
        gasFee = _storage.configTable.getUint256(MCO_ORDER_GAS_FEE_GWEI);
        // 0 is valid
    }

    function _balance(address token) internal view returns (uint256) {
        return IERC20Upgradeable(token).balanceOf(address(this));
    }
}
