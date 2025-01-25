// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IOrderBook as IMux3OrderBook, IOrderBookGetter as IMux3OrderBookGetter, PositionOrderParams as Mux3PositionOrderParams } from "../interfaces/IOrderBook.sol";
import { WithdrawalOrderParams as Mux3WithdrawalOrderParams, WithdrawAllOrderParams as Mux3WithdrawAllOrderParams } from "../interfaces/IOrderBook.sol";
import { OrderData as Mux3OrderData, ModifyPositionOrderParams as Mux3ModifyPositionOrderParams } from "../interfaces/IOrderBook.sol";
import { LibCodec as LibMux3Codec } from "../libraries/LibCodec.sol";

contract Delegator is Initializable {
    event SetDelegator(address indexed owner, address indexed delegator, uint256 actionCount);

    struct Delegation {
        address delegator;
        uint256 actionCount;
    }

    address internal _mux3OrderBook;
    mapping(address => Delegation) internal _reserved1; // was delegator => Delegation
    mapping(address => Delegation) internal _delegations; // owner => Delegation
    uint256 internal _reserved2; // was _actionCountDeductedInTx

    function initialize(address mux3OrderBook) external initializer {
        require(mux3OrderBook != address(0), "Invalid order book address");
        _mux3OrderBook = mux3OrderBook;
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

    /**
     * @notice Executes multiple function calls in a single transaction
     *
     *         note: Delegator.multicall is slightly different from OrderBook.multicall,
     *               Delegator does not support wrap ETH as collateral (WETH is supported).
     * @param proxyCalls Array of function calls to execute
     * @return results Array of return values from each call
     * @dev Trader/LP can wrap ETH to OrderBook, transfer ERC20 to OrderBook, placeOrders
     *
     *      example for collateral = USDC or WETH:
     *        multicall([
     *          mux3DepositGas(gas),
     *          mux3TransferToken(collateral),
     *          mux3PlacePositionOrder(positionOrderParams),
     *        ])
     */
    function multicall(bytes[] calldata proxyCalls) external payable returns (bytes[] memory results) {
        results = new bytes[](proxyCalls.length);
        for (uint256 i = 0; i < proxyCalls.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(proxyCalls[i]);
            AddressUpgradeable.verifyCallResult(success, returnData, "multicallFailed");
            results[i] = returnData;
        }
    }

    /**
     * @notice MUX3: Trader should pay for gas for their orders
     *         you should pay at least configValue(MCO_ORDER_GAS_FEE_GWEI) * 1e9 / 1e18 ETH for each order
     *
     *         note: Delegator.depositGas is slightly different from OrderBook.depositGas,
     *               there is no Delegator.wrapNative, and Delegator.depositGas consumes msg.value and deposit it as gas to OrderBook.
     */
    function mux3DepositGas(address owner, uint256 amount) external payable {
        _consumeDelegation(owner, 0);
        IMux3OrderBook(_mux3OrderBook).wrapNative{ value: amount }(amount);
        IMux3OrderBook(_mux3OrderBook).depositGas(owner, amount);
    }

    /**
     * @notice MUX3: Trader transfer ERC20 tokens (usually collaterals) to the OrderBook
     *
     *         note: transferToken is intended to be used as part of a multicall. If it is called directly
     *               the caller would end up losing the funds.
     * @param owner Address of the owner of the tokens
     * @param token Address of the token to transfer
     * @param amount Amount of tokens to transfer
     */
    function mux3TransferToken(address owner, address token, uint256 amount) external payable {
        _consumeDelegation(owner, 0);
        IMux3OrderBook(_mux3OrderBook).transferTokenFrom(owner, token, amount);
    }

    /**
     * @notice MUX3: A Trader can open/close position
     *         Market order will expire after marketOrderTimeout seconds.
     *         Limit/Trigger order will expire after deadline.
     * @param orderParams The parameters for the position order
     * @param referralCode The referral code for the position order
     * @dev depositGas required (consume gas when filled)
     */
    function mux3PlacePositionOrder(Mux3PositionOrderParams memory orderParams, bytes32 referralCode) external payable {
        (address owner, ) = LibMux3Codec.decodePositionId(orderParams.positionId);
        _consumeDelegation(owner, 1);
        IMux3OrderBook(_mux3OrderBook).placePositionOrder(orderParams, referralCode);
    }

    /**
     * @notice MUX3: A Trader/LP can cancel an Order by orderId after a cool down period.
     *         A Broker can also cancel an Order after expiration.
     * @param orderId The ID of the order to cancel
     */
    function mux3CancelOrder(uint64 orderId) external payable {
        (Mux3OrderData memory orderData, bool exists) = IMux3OrderBookGetter(_mux3OrderBook).getOrder(orderId);
        require(exists, "No such orderId");
        address owner = orderData.account;
        _consumeDelegation(owner, 1);
        IMux3OrderBook(_mux3OrderBook).cancelOrder(orderId);
    }

    /**
     * @notice MUX3: A Trader can withdraw collateral
     *         This order will expire after marketOrderTimeout seconds.
     * @param orderParams The parameters for the withdrawal order
     * @dev depositGas required (consume gas when filled)
     */
    function mux3PlaceWithdrawalOrder(Mux3WithdrawalOrderParams memory orderParams) external payable {
        (address owner, ) = LibMux3Codec.decodePositionId(orderParams.positionId);
        _consumeDelegation(owner, 1);
        IMux3OrderBook(_mux3OrderBook).placeWithdrawalOrder(orderParams);
    }

    /**
     * @notice MUX3: A Trader can withdraw all collateral only when position = 0
     * @param orderParams The parameters for the withdrawal order
     * @dev do not need depositGas
     */
    function mux3WithdrawAllCollateral(Mux3WithdrawAllOrderParams memory orderParams) external payable {
        (address owner, ) = LibMux3Codec.decodePositionId(orderParams.positionId);
        _consumeDelegation(owner, 1);
        IMux3OrderBook(_mux3OrderBook).withdrawAllCollateral(orderParams);
    }

    /**
     * @notice MUX3: A Trader can deposit collateral into a PositionAccount
     * @param positionId The ID of the position
     * @param collateralToken The address of the collateral token
     * @param collateralAmount The amount of collateral token
     * @dev do not need depositGas
     */
    function mux3DepositCollateral(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount // token decimals
    ) external payable {
        (address owner, ) = LibMux3Codec.decodePositionId(positionId);
        _consumeDelegation(owner, 0);
        IMux3OrderBook(_mux3OrderBook).depositCollateral(positionId, collateralToken, collateralAmount);
    }

    /**
     * @notice MUX3: A trader should set initial leverage at least once before open-position
     * @param positionId The ID of the position
     * @param marketId The ID of the market
     * @param initialLeverage The initial leverage to set
     * @dev do not need depositGas
     */
    function mux3SetInitialLeverage(bytes32 positionId, bytes32 marketId, uint256 initialLeverage) external payable {
        (address owner, ) = LibMux3Codec.decodePositionId(positionId);
        _consumeDelegation(owner, 0);
        IMux3OrderBook(_mux3OrderBook).setInitialLeverage(positionId, marketId, initialLeverage);
    }

    /**
     * @notice MUX3: A Trader can modify a position order
     * @param orderParams The parameters for the modify position order
     * @dev do not need depositGas
     */
    function mux3ModifyPositionOrder(Mux3ModifyPositionOrderParams memory orderParams) external payable {
        (address owner, ) = LibMux3Codec.decodePositionId(orderParams.positionId);
        _consumeDelegation(owner, 1);
        IMux3OrderBook(_mux3OrderBook).modifyPositionOrder(orderParams);
    }

    function _consumeDelegation(address owner, uint256 deductActionCount) private {
        address delegator = msg.sender;
        Delegation storage delegation = _delegations[owner];
        require(delegation.delegator == delegator, "Not authorized");
        require(delegation.actionCount > 0, "No action count"); // actionCount = 0 is the same as no delegation
        delegation.actionCount -= deductActionCount;
    }
}
