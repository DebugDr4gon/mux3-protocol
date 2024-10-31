// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

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
        require(orderBook != address(0), "Invalid order book address");
        _orderBook = orderBook;
    }

    function getDelegation(
        address delegator
    ) external view returns (Delegation memory) {
        return _delegators[delegator];
    }

    function delegate(address delegator, uint256 actionCount) public payable {
        address owner = msg.sender;
        require(delegator != address(0), "Invalid delegator address");
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
        require(delegation.owner != address(0), "Not delegated");
        require(delegation.actionCount > 0, "No action count");
        delegation.actionCount--;
        IOrderBook(_orderBook).transferTokenFrom(
            delegation.owner,
            token,
            amount
        );
    }

    function _consumeDelegation(address expectedOwner) private {
        address delegator = msg.sender;
        Delegation storage delegation = _delegators[delegator];
        require(delegation.owner != address(0), "Not delegated");
        require(delegation.actionCount > 0, "No action count");
        delegation.actionCount--;
        require(delegation.owner == expectedOwner, "Not authorized");
    }

    function placePositionOrder(
        PositionOrderParams memory orderParams,
        bytes32 referralCode
    ) external {
        (address positionAccount, ) = LibCodec.decodePositionId(
            orderParams.positionId
        );
        _consumeDelegation(positionAccount);
        IOrderBook(_orderBook).placePositionOrder(orderParams, referralCode);
    }

    function cancelOrder(uint64 orderId) external {
        (OrderData memory orderData, bool exists) = IOrderBookGetter(_orderBook)
            .getOrder(orderId);
        require(exists, "Order not exists");
        _consumeDelegation(orderData.account);
        IOrderBook(_orderBook).cancelOrder(orderId);
    }

    function placeWithdrawalOrder(
        WithdrawalOrderParams memory orderParams
    ) external {
        (address positionAccount, ) = LibCodec.decodePositionId(
            orderParams.positionId
        );
        _consumeDelegation(positionAccount);
        IOrderBook(_orderBook).placeWithdrawalOrder(orderParams);
    }

    function withdrawAllCollateral(bytes32 positionId) external {
        (address positionAccount, ) = LibCodec.decodePositionId(positionId);
        _consumeDelegation(positionAccount);
        IOrderBook(_orderBook).withdrawAllCollateral(positionId);
    }

    function depositCollateral(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount // token decimals
    ) external {
        (address positionAccount, ) = LibCodec.decodePositionId(positionId);
        _consumeDelegation(positionAccount);
        IOrderBook(_orderBook).depositCollateral(
            positionId,
            collateralToken,
            collateralAmount
        );
    }

    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 initialLeverage
    ) external {
        (address positionAccount, ) = LibCodec.decodePositionId(positionId);
        _consumeDelegation(positionAccount);
        IOrderBook(_orderBook).setInitialLeverage(
            positionId,
            marketId,
            initialLeverage
        );
    }
}
