// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IOrderBook.sol";
import "../interfaces/IWETH9.sol";
import "../libraries/LibConfigTable.sol";
import "../libraries/LibOrderBook.sol";
import "../libraries/LibCodec.sol";
import "./OrderBookStore.sol";
import "./OrderBookGetter.sol";
import "./PriceProvider.sol";

contract OrderBook is
    OrderBookStore,
    ReentrancyGuardUpgradeable,
    OrderBookGetter,
    PriceProvider,
    IOrderBook
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    modifier whenNotPaused(OrderType orderType) {
        require(!isOrderPaused(orderType), "Paused");
        _;
    }

    modifier updateSequence() {
        _;
        unchecked {
            _storage.sequence += 1;
        }
        emit UpdateSequence(_storage.sequence);
    }

    function initialize(address mux3Facet, address weth) external initializer {
        __AccessControlEnumerable_init();
        _storage.mux3Facet = mux3Facet;
        _storage.weth = weth;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MAINTAINER_ROLE, msg.sender);
    }

    /**
     * @dev Trader/LP can wrap ETH to OrderBook, transfer ERC20 to OrderBook, placeOrders
     */
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

    /**
     * @dev Trader/LP can wrap ETH to OrderBook
     */
    function wrapNative() external payable {
        IWETH9(_storage.weth).deposit{ value: msg.value }();
    }

    /**
     * @dev Trader/LP can transfer ERC20 to OrderBook
     */
    function transferToken(address token, uint256 amount) external {
        IERC20Upgradeable(token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    /**
     * @dev Delegator can transfer ERC20 from Trader/LP to OrderBook
     */
    function transferTokenFrom(
        address from,
        address token,
        uint256 amount
    ) external {
        require(_isDelegator(msg.sender), "delegator only");
        IERC20Upgradeable(token).safeTransferFrom(from, address(this), amount);
    }

    /**
     * @notice Open/close position. called by Trader.
     *
     *         Market order will expire after marketOrderTimeout seconds.
     *         Limit/Trigger order will expire after deadline.
     */
    function placePositionOrder(
        PositionOrderParams memory orderParams,
        bytes32 referralCode
    ) public nonReentrant whenNotPaused(OrderType.PositionOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(
            orderParams.positionId
        );
        if (_isDelegator(msg.sender)) {} else {
            require(positionAccount == msg.sender, "not authorized");
        }
        // TODO: referral code
        // address referralManager = _referralManager();
        // if (referralCode != bytes32(0) && referralManager != address(0)) {
        //     IReferralManager(referralManager).setReferrerCodeFor(
        //         positionAccount,
        //         referralCode
        //     );
        // }
        LibOrderBook.placePositionOrder(
            _storage,
            orderParams,
            _blockTimestamp()
        );
    }

    /**
     * @notice Add/remove liquidity. called by Liquidity Provider.
     *
     *         Can be filled after liquidityLockPeriod seconds.
     * @param  orderParams   order details includes:
     *         assetId       asset.id that added/removed to.
     *         rawAmount     asset token amount. decimals = erc20.decimals.
     *         isAdding      true for add liquidity, false for remove liquidity.
     */
    function placeLiquidityOrder(
        LiquidityOrderParams memory orderParams
    ) external nonReentrant whenNotPaused(OrderType.LiquidityOrder) {
        LibOrderBook.placeLiquidityOrder(
            _storage,
            orderParams,
            msg.sender,
            _blockTimestamp()
        );
    }

    /**
     * @notice Withdraw collateral/profit. called by Trader.
     *
     *         This order will expire after marketOrderTimeout seconds.
     */
    function placeWithdrawalOrder(
        WithdrawalOrderParams memory orderParams
    ) external nonReentrant whenNotPaused(OrderType.WithdrawalOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(
            orderParams.positionId
        );
        require(positionAccount == msg.sender, "not authorized");
        LibOrderBook.placeWithdrawalOrder(
            _storage,
            orderParams,
            _blockTimestamp()
        );
    }

    /**
     * @dev   Open/close a position. called by Broker.
     */
    function fillPositionOrder(
        uint64 orderId,
        uint256[] memory packedPrices
    )
        external
        onlyRole(BROKER_ROLE)
        nonReentrant
        whenNotPaused(OrderType.PositionOrder)
        updateSequence
        returns (uint256 tradingPrice)
    {
        return
            LibOrderBook.fillPositionOrder(
                _storage,
                _configTable,
                orderId,
                _blockTimestamp()
            );
    }

    /**
     * @dev   Add/remove liquidity. called by Broker.
     */
    function fillLiquidityOrder(
        uint64 orderId,
        uint256[] memory packedPrices
    )
        external
        onlyRole(BROKER_ROLE)
        whenNotPaused(OrderType.LiquidityOrder)
        nonReentrant
        updateSequence
        returns (uint256 outAmount)
    {
        return
            LibOrderBook.fillLiquidityOrder(
                _storage,
                _configTable,
                orderId,
                _blockTimestamp()
            );
    }

    // function donateLiquidity(
    //     uint8 assetId,
    //     uint96 rawAmount // erc20.decimals
    // ) external updateSequence {
    //     _storage.donateLiquidity(msg.sender, assetId, rawAmount);
    // }
    /**
     * @dev   Withdraw collateral/profit. called by Broker.
     *
     * @param orderId           order id.
     * @param markPrices        mark prices of all assets. decimals = 18.
     */
    // function fillWithdrawalOrder(
    //     uint64 orderId,
    //     uint96[] memory markPrices
    // )
    //     external
    //     onlyRole(BROKER_ROLE)
    //     whenNotPaused(OrderType.WithdrawalOrder)
    //     nonReentrant
    //     updateSequence
    // {
    //     require(_storage.orders.contains(orderId), "OID"); // can not find this OrderID
    //     OrderData memory orderData = _storage.orderData[orderId];
    //     _storage.removeOrder(orderData);
    //     require(orderData.orderType == OrderType.WithdrawalOrder, "TYP"); // order TYPe mismatch
    //     WithdrawalOrderParams memory orderParams = orderData
    //         .decodeWithdrawalOrder();
    //     require(
    //         _blockTimestamp() <=
    //             orderData.placeOrderTime + _marketOrderTimeout(),
    //         "EXP"
    //     ); // EXPired
    //     // update funding state
    //     IDegenPool(_storage.pool).updateFundingState();
    //     // fill
    //     if (orderParams.isProfit) {
    //         require(false, "PFT"); // withdraw profit is not supported yet
    //     } else {
    //         uint96 collateralPrice = markPrices[
    //             orderParams.subAccountId.collateralId()
    //         ];
    //         uint96 assetPrice = markPrices[orderParams.subAccountId.assetId()];
    //         IDegenPool(_storage.pool).withdrawCollateral(
    //             orderParams.subAccountId,
    //             orderParams.rawAmount,
    //             collateralPrice,
    //             assetPrice
    //         );
    //     }
    //     emit FillOrder(orderData.account, orderId, orderData);
    // }
    /**
     * @notice Cancel an Order by orderId.
     */
    function cancelOrder(uint64 orderId) external nonReentrant updateSequence {
        LibOrderBook.cancelOrder(
            _storage,
            _configTable,
            orderId,
            _blockTimestamp(),
            msg.sender
        );
    }

    // function _cancelLiquidityOrder(
    //     LiquidityOrderParams memory orderParams,
    //     address account
    // ) internal {
    //     if (orderParams.isAdding) {
    //         address collateralAddress = IDegenPool(_storage.pool)
    //             .getAssetParameter(
    //                 orderParams.assetId,
    //                 LibConfigKeys.TOKEN_ADDRESS
    //             )
    //             .toAddress();
    //         LibOrderBook._transferOut(
    //             collateralAddress,
    //             account,
    //             orderParams.rawAmount
    //         );
    //     } else {
    //         LibOrderBook.transferOut(_storage.mlpToken,
    //             account,
    //             orderParams.rawAmount
    //         );
    //     }
    //     // if (_storage.callbackWhitelist[orderParams.account]) {
    //     //     try
    //     //         ILiquidityCallback(orderParams.account).afterCancelLiquidityOrder{ gas: _callbackGasLimit() }(order)
    //     //     {} catch {}
    //     // }
    // }
    /**
     * @notice Trader can withdraw all collateral only when position = 0.
     */
    function withdrawAllCollateral(
        bytes32 positionId
    ) external updateSequence whenNotPaused(OrderType.WithdrawalOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(positionId);
        require(positionAccount == msg.sender, "not authorized");
        LibOrderBook.withdrawAllCollateral(_storage, positionId);
    }

    /**
     * @notice Deposit collateral into a subAccount.
     */
    function depositCollateral(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount // token decimals
    ) external updateSequence {
        LibOrderBook.depositCollateral(
            _storage,
            _configTable,
            positionId,
            collateralToken,
            collateralAmount
        );
    }

    // function liquidate(
    //     bytes32 subAccountId,
    //     uint8 profitAssetId, // only used when !isLong
    //     uint96 tradingPrice,
    //     uint96[] memory assetPrices
    // ) external onlyRole(BROKER_ROLE) updateSequence {
    //     // update funding state
    //     IDegenPool(_storage.pool).updateFundingState();
    //     // fill
    //     IDegenPool(_storage.pool).liquidate(
    //         subAccountId,
    //         profitAssetId,
    //         tradingPrice,
    //         assetPrices
    //     );
    //     // auto withdraw
    //     (uint96 collateral, , , , ) = IDegenPool(_storage.pool).getSubAccount(
    //         subAccountId
    //     );
    //     if (collateral > 0) {
    //         IDegenPool(_storage.pool).withdrawAllCollateral(subAccountId);
    //     }
    //     // cancel activated tp/sl orders
    //     _storage.cancelActivatedTpslOrders(subAccountId);
    // }
    // function fillAdlOrder(
    //     AdlOrderParams memory orderParams,
    //     uint96 tradingPrice,
    //     uint96[] memory markPrices
    // ) public onlyRole(BROKER_ROLE) nonReentrant updateSequence {
    //     // update funding state
    //     IDegenPool(_storage.pool).updateFundingState();
    //     // fill
    //     _storage.fillAdlOrder(orderParams, tradingPrice, markPrices);
    // }
    // /**
    //  * @dev Broker can withdraw brokerGasRebate.
    //  */
    // function claimBrokerGasRebate(
    //     uint8 assetId
    // ) external onlyRole(BROKER_ROLE) returns (uint256 rawAmount) updateSequence {
    //     return
    //         IDegenPool(_storage.pool).claimBrokerGasRebate(
    //             msg.sender,
    //             assetId
    //         );
    // }
    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function setConfig(bytes32 key, bytes32 value) external updateSequence {
        _checkRole(MAINTAINER_ROLE, msg.sender);
        // TODO: add test rules for specified key
        LibConfigTable.setBytes32(_configTable, key, value);
    }

    // TODO: remove me if oracleProvider is ready
    function setMockPrice(
        bytes32 key,
        uint256 price
    ) external onlyRole(BROKER_ROLE) nonReentrant {
        MockPriceSetter(_storage.mux3Facet).setMockPrice(key, price);
    }
}

// TODO: remove me if oracleProvider is ready
interface MockPriceSetter {
    function setMockPrice(bytes32 key, uint256 price) external;
}
