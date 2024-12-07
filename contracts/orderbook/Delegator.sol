// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IOrderBook.sol";
import "../libraries/LibCodec.sol";

contract Delegator is Initializable {
    event SetDelegator(address indexed owner, address indexed delegator, uint256 actionCount);

    struct Delegation {
        address delegator;
        uint256 actionCount;
    }

    address internal _orderBook;
    mapping(address => Delegation) internal _reserved1; // was delegator => Delegation
    mapping(address => Delegation) internal _delegations; // owner => Delegation

    function initialize(address orderBook) external initializer {
        require(orderBook != address(0), "Invalid order book address");
        _orderBook = orderBook;
    }

    function getDelegationByOwner(address owner) external view returns (Delegation memory) {
        return _delegations[owner];
    }

    /**
     * @notice A cold-wallet (msg.sender) can approve a hot-wallet (delegator) to act on its behalf.
     *         The hot-wallet can then deposit collateral from the cold-wallet into a PositionAccount,
     *         and openPositions on behalf of the cold-wallet.
     */
    function delegate(address delegator, uint256 actionCount) public payable {
        address owner = msg.sender;
        require(delegator != address(0), "Invalid delegator address");
        _delegations[owner] = Delegation(delegator, actionCount);
        if (msg.value > 0) {
            // forward eth to delegator
            AddressUpgradeable.sendValue(payable(delegator), msg.value);
        }
    }

    // check OrderBook for more details
    function multicall(bytes[] calldata proxyCalls) external payable returns (bytes[] memory results) {
        results = new bytes[](proxyCalls.length);
        for (uint256 i = 0; i < proxyCalls.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(proxyCalls[i]);
            AddressUpgradeable.verifyCallResult(success, returnData, "multicallFailed");
            results[i] = returnData;
        }
    }

    // check OrderBook for more details
    function transferToken(address owner, address token, uint256 amount) external {
        _consumeDelegation(owner);
        IOrderBook(_orderBook).transferTokenFrom(owner, token, amount);
    }

    function placePositionOrder(PositionOrderParams memory orderParams, bytes32 referralCode) external {
        (address owner, ) = LibCodec.decodePositionId(orderParams.positionId);
        _consumeDelegation(owner);
        IOrderBook(_orderBook).placePositionOrder(orderParams, referralCode);
    }

    function cancelOrder(uint64 orderId) external {
        (OrderData memory orderData, bool exists) = IOrderBookGetter(_orderBook).getOrder(orderId);
        require(exists, "No such orderId");
        address owner = orderData.account;
        _consumeDelegation(owner);
        IOrderBook(_orderBook).cancelOrder(orderId);
    }

    function placeWithdrawalOrder(WithdrawalOrderParams memory orderParams) external {
        (address owner, ) = LibCodec.decodePositionId(orderParams.positionId);
        _consumeDelegation(owner);
        IOrderBook(_orderBook).placeWithdrawalOrder(orderParams);
    }

    function withdrawAllCollateral(WithdrawAllOrderParams memory orderParams) external {
        (address owner, ) = LibCodec.decodePositionId(orderParams.positionId);
        _consumeDelegation(owner);
        IOrderBook(_orderBook).withdrawAllCollateral(orderParams);
    }

    function depositCollateral(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount // token decimals
    ) external {
        (address owner, ) = LibCodec.decodePositionId(positionId);
        _consumeDelegation(owner);
        IOrderBook(_orderBook).depositCollateral(positionId, collateralToken, collateralAmount);
    }

    function setInitialLeverage(bytes32 positionId, bytes32 marketId, uint256 initialLeverage) external {
        (address owner, ) = LibCodec.decodePositionId(positionId);
        _consumeDelegation(owner);
        IOrderBook(_orderBook).setInitialLeverage(positionId, marketId, initialLeverage);
    }

    function _consumeDelegation(address owner) private {
        address delegator = msg.sender;
        Delegation storage delegation = _delegations[owner];
        require(delegation.delegator == delegator, "Not authorized");
        require(delegation.actionCount > 0, "No action count");
        delegation.actionCount--;
    }
}
