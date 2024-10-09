// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IOrderBook.sol";
import "../libraries/LibCodec.sol";

contract Delegator is Initializable {
    event SetDeletaor(
        address indexed owner,
        address indexed delegator,
        uint256 actionCount
    );

    struct Delegation {
        address owner;
        uint256 actionCount;
    }

    address internal _orderBook;
    mapping(address => Delegation) internal _delegators;

    function initialize(address orderBook) external initializer {
        _orderBook = orderBook;
    }

    function getDelegation(
        address delegator
    ) external view returns (Delegation memory) {
        return _delegators[delegator];
    }

    function delegate(address delegator, uint256 actionCount) public payable {
        address owner = msg.sender;
        require(delegator != address(0), "invalid address");
        _delegators[delegator] = Delegation(owner, actionCount);
        if (msg.value > 0) {
            // forward eth to delegator
            AddressUpgradeable.sendValue(payable(delegator), msg.value);
        }
    }

    function multicall(
        bytes[] calldata proxyCalls
    ) external payable returns (bytes[] memory results) {
        results = new bytes[](proxyCalls.length);
        for (uint256 i = 0; i < proxyCalls.length; i++) {
            (bool success, bytes memory returnData) = address(this)
                .delegatecall(proxyCalls[i]);
            AddressUpgradeable.verifyCallResult(
                success,
                returnData,
                "multicallFailed"
            );
            results[i] = returnData;
        }
    }

    function transferToken(address token, uint256 amount) external {
        address delegator = msg.sender;
        Delegation storage delegation = _delegators[delegator];
        require(delegation.owner != address(0), "not delegated");
        require(delegation.actionCount > 0, "no action count");
        delegation.actionCount--;
        IOrderBook(_orderBook).transferTokenFrom(
            delegation.owner,
            token,
            amount
        );
    }

    function placePositionOrder(
        PositionOrderParams memory orderParams,
        bytes32 referralCode
    ) external {
        address delegator = msg.sender;
        Delegation storage delegation = _delegators[delegator];
        require(delegation.owner != address(0), "not delegated");
        require(delegation.actionCount > 0, "no action count");
        delegation.actionCount--;
        (address positionAccount, ) = LibCodec.decodePositionId(
            orderParams.positionId
        );
        require(positionAccount == delegation.owner, "not authorized");
        IOrderBook(_orderBook).placePositionOrder(orderParams, referralCode);
    }

    function cancelOrder(uint64 orderId) external {
        address delegator = msg.sender;
        Delegation storage delegation = _delegators[delegator];
        require(delegation.owner != address(0), "not delegated");
        require(delegation.actionCount > 0, "no action count");
        delegation.actionCount--;
        (OrderData memory orderData, bool exists) = IOrderBookGetter(_orderBook)
            .getOrder(orderId);
        require(exists, "order not exists");
        require(orderData.account == delegation.owner, "not authorized");
        require(
            orderData.orderType == OrderType.PositionOrder,
            "invalid order type"
        );
        IOrderBook(_orderBook).cancelOrder(orderId);
    }
}
