// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

// import "../interfaces/IReferralManager.sol"; TODO
import "../interfaces/IOrderBook.sol";
import "../interfaces/IMux3Core.sol";
import "../interfaces/IMarket.sol";
import "../interfaces/ICollateralPool.sol";
import "../interfaces/IWETH9.sol";
import "../libraries/LibOrder.sol";
import "../libraries/LibConfigMap.sol";
import "../libraries/LibCodec.sol";

library LibOrderBook {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibTypeCast for bytes32;
    using LibTypeCast for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using LibConfigMap for mapping(bytes32 => bytes32);

    function _appendOrder(
        OrderBookStorage storage orderBook,
        OrderData memory orderData
    ) internal {
        orderBook.orderData[orderData.id] = orderData;
        require(
            orderBook.orders.add(orderData.id) &&
                orderBook.userOrders[orderData.account].add(orderData.id),
            "Failed to append order"
        );
    }

    function _removeOrder(
        OrderBookStorage storage orderBook,
        OrderData memory orderData
    ) internal {
        require(
            orderBook.userOrders[orderData.account].remove(orderData.id) &&
                orderBook.orders.remove(orderData.id),
            "Failed to remove order"
        );
        delete orderBook.orderData[orderData.id];
    }

    function placeLiquidityOrder(
        OrderBookStorage storage orderBook,
        LiquidityOrderParams memory orderParams,
        address account,
        uint256 blockTimestamp
    ) external {
        require(orderParams.rawAmount != 0, "Zero amount");
        _validatePool(orderBook, orderParams.poolAddress);
        if (orderParams.isAdding) {
            address collateralAddress = ICollateralPool(orderParams.poolAddress)
                .collateralToken();
            _transferIn(orderBook, collateralAddress, orderParams.rawAmount);
        } else {
            _transferIn(
                orderBook,
                orderParams.poolAddress,
                orderParams.rawAmount
            );
        }
        uint64 orderId = orderBook.nextOrderId++;
        OrderData memory orderData = LibOrder.encodeLiquidityOrder(
            orderParams,
            orderId,
            account,
            blockTimestamp
        );
        _appendOrder(orderBook, orderData);
        emit IOrderBook.NewLiquidityOrder(account, orderId, orderParams);
    }

    function fillLiquidityOrder(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        uint64 orderId,
        uint256 blockTimestamp
    ) external returns (uint256 outAmount) {
        require(orderBook.orders.contains(orderId), "No such orderId");
        OrderData memory orderData = orderBook.orderData[orderId];
        _removeOrder(orderBook, orderData);
        require(
            orderData.orderType == OrderType.LiquidityOrder,
            "Order type mismatch"
        );
        // fill
        LiquidityOrderParams memory orderParams = LibOrder.decodeLiquidityOrder(
            orderData
        );
        uint256 lockPeriod = _liquidityLockPeriod(configTable);
        require(
            blockTimestamp >= orderData.placeOrderTime + lockPeriod,
            "Liquidity order is under lock period"
        );
        if (orderParams.isAdding) {
            address collateralAddress = ICollateralPool(orderParams.poolAddress)
                .collateralToken();
            _transferOut(
                orderBook,
                configTable,
                collateralAddress, // token
                orderParams.poolAddress, // receipt
                orderParams.rawAmount,
                false // unwrap eth
            );
            outAmount = ICollateralPool(orderParams.poolAddress).addLiquidity(
                orderData.account,
                orderParams.rawAmount
            );
        } else {
            // note: lp token is still in the OrderBook
            outAmount = ICollateralPool(orderParams.poolAddress)
                .removeLiquidity(orderData.account, orderParams.rawAmount);
        }
        emit IOrderBook.FillOrder(orderData.account, orderId, orderData);
    }

    // function donateLiquidity(
    //     OrderBookStorage storage orderBook,
    //     address account,
    //     uint8 assetId,
    //     uint96 rawAmount // erc20.decimals
    // ) external {
    //     require(rawAmount != 0, "Zero amount");
    //     address collateralAddress = IDegenPool(orderBook.pool)
    //         .getAssetParameter(assetId, LibConfigKeys.TOKEN_ADDRESS)
    //         .toAddress();
    //     _transferIn(orderBook, collateralAddress, rawAmount);
    //     _transferOut(orderBook, configTable, collateralAddress, rawAmount, poolAddress, false);
    //     IDegenPool(orderBook.pool).donateLiquidity(account, assetId, rawAmount);
    // }

    function fillWithdrawalOrder(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        uint64 orderId,
        uint256 blockTimestamp
    ) external {
        require(orderBook.orders.contains(orderId), "No such orderId");
        OrderData memory orderData = orderBook.orderData[orderId];
        _removeOrder(orderBook, orderData);
        require(
            orderData.orderType == OrderType.WithdrawalOrder,
            "Order type mismatch"
        );
        WithdrawalOrderParams memory orderParams = LibOrder
            .decodeWithdrawalOrder(orderData);
        uint256 deadline = orderData.placeOrderTime +
            _withdrawalOrderTimeout(configTable);
        require(blockTimestamp <= deadline, "Order expired");
        // fill
        IPositionAccount(orderBook.mux3Facet).withdraw(
            orderParams.positionId,
            orderParams.tokenAddress,
            orderParams.rawAmount
            // TODO: check isUnwrapWeth
        );

        emit IOrderBook.FillOrder(orderData.account, orderId, orderData);
    }

    function placePositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint256 blockTimestamp
    ) external {
        _validateMarketId(orderBook, orderParams.marketId);
        require(orderParams.size != 0, "Position order size = 0");
        {
            uint256 lotSize = _lotSize(orderBook, orderParams.marketId);
            require(
                orderParams.size % lotSize == 0,
                "size must be a multiple of lot size"
            );
        }
        require(!LibOrder.isAdl(orderParams), "ADL is not allowed");
        require(
            orderParams.limitPrice > 0,
            "Position order must have limitPrice"
        );
        require(
            orderParams.expiration > blockTimestamp,
            "Expiration is earlier than now"
        );
        if (orderParams.initialLeverage > 0) {
            IPositionAccount(orderBook.mux3Facet).setInitialLeverage(
                orderParams.positionId,
                orderParams.marketId,
                orderParams.initialLeverage
            );
        }
        if (LibOrder.isOpenPosition(orderParams)) {
            _placeOpenPositionOrder(orderBook, orderParams, blockTimestamp);
        } else {
            _placeClosePositionOrder(orderBook, orderParams, blockTimestamp);
        }
    }

    function _placeOpenPositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint256 blockTimestamp
    ) private {
        require(
            orderParams.withdrawUsd == 0,
            "WithdrawUsd is not suitable for open-position"
        );
        require(
            orderParams.lastWithdrawToken == address(0),
            "LastWithdrawToken is not suitable for open-position"
        );
        require(
            orderParams.withdrawSwapToken == address(0),
            "WithdrawSwapToken is not suitable for open-position"
        );
        require(
            orderParams.withdrawSwapSlippage == 0,
            "WithdrawSwapSlippage is not suitable for open-position"
        );
        // fetch collateral
        if (orderParams.collateralToken != address(0)) {
            _validateCollateral(orderBook, orderParams.collateralToken);
            if (orderParams.collateralAmount > 0) {
                // deposit collateral
                _transferIn(
                    orderBook,
                    orderParams.collateralToken,
                    orderParams.collateralAmount
                );
            }
        }
        // add order
        _appendPositionOrder(orderBook, orderParams, blockTimestamp);
        // tp/sl strategy
        if (orderParams.tpPriceDiff > 0 || orderParams.slPriceDiff > 0) {
            require(
                orderParams.tpslExpiration > blockTimestamp,
                "tpslExpiration is earlier than now"
            );
            uint256 validFlags = POSITION_WITHDRAW_ALL_IF_EMPTY |
                POSITION_WITHDRAW_PROFIT |
                POSITION_UNWRAP_ETH;
            require(
                (orderParams.tpslFlags & (~validFlags)) == 0,
                "Unsupported tpslFlags"
            );
            if (orderParams.tpslLastWithdrawToken != address(0)) {
                _validateCollateral(
                    orderBook,
                    orderParams.tpslLastWithdrawToken
                );
            }
            if (orderParams.tpslWithdrawSwapToken != address(0)) {
                _validateCollateral(
                    orderBook,
                    orderParams.tpslWithdrawSwapToken
                );
            }
        }
    }

    function _placeClosePositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint256 blockTimestamp
    ) private {
        require(
            orderParams.collateralToken == address(0) &&
                orderParams.collateralAmount == 0,
            "Use withdraw instead"
        );
        if (orderParams.lastWithdrawToken != address(0)) {
            _validateCollateral(orderBook, orderParams.lastWithdrawToken);
        }
        if (orderParams.withdrawSwapToken != address(0)) {
            _validateCollateral(orderBook, orderParams.withdrawSwapToken);
        }
        _appendPositionOrder(orderBook, orderParams, blockTimestamp);
        // tp/sl strategy is not supported
        require(
            orderParams.tpPriceDiff == 0 &&
                orderParams.slPriceDiff == 0 &&
                orderParams.tpslExpiration == 0 &&
                orderParams.tpslFlags == 0 &&
                orderParams.tpslLastWithdrawToken == address(0) &&
                orderParams.tpslWithdrawSwapToken == address(0) &&
                orderParams.tpslWithdrawSwapSlippage == 0,
            "Place multiple close-position orders instead"
        );
    }

    // function cancelActivatedTpslOrders(
    //     OrderBookStorage storage orderBook,
    //     bytes32 subAccountId
    // ) public {
    //     EnumerableSetUpgradeable.UintSet storage orderIds = orderBook
    //         .tpslOrders[subAccountId];
    //     uint256 length = orderIds.length();
    //     for (uint256 i = 0; i < length; i++) {
    //         uint64 orderId = uint64(orderIds.at(i));
    //         require(orderBook.orders.contains(orderId), "No such orderId");
    //         OrderData memory orderData = orderBook.orderData[orderId];
    //         OrderType orderType = OrderType(orderData.orderType);
    //         require(orderType == OrderType.PositionOrder, "Order type mismatch");
    //         PositionOrderParams memory orderParams = orderData
    //             .decodePositionOrder();
    //         require(
    //             !orderParams.isOpenPosition() && orderParams.collateral == 0,
    //             "TP/SL order should be a CLOSE order and without collateralAmount");
    //         removeOrder(orderBook, orderData);
    //         emit IOrderBook.CancelOrder(orderData.account, orderId, orderData);
    //     }
    //     delete orderBook.tpslOrders[subAccountId]; // tp/sl strategy
    // }
    function withdrawAllCollateral(
        OrderBookStorage storage orderBook,
        bytes32 positionId
    ) external {
        require(
            _isPositionAccountFullyClosed(orderBook, positionId),
            "Position account is not fully closed"
        );
        IPositionAccount(orderBook.mux3Facet).withdrawAll(positionId);
    }

    function placeWithdrawalOrder(
        OrderBookStorage storage orderBook,
        WithdrawalOrderParams memory orderParams,
        uint256 blockTimestamp
    ) external {
        (address withdrawAccount, ) = LibCodec.decodePositionId(
            orderParams.positionId
        );
        require(orderParams.rawAmount != 0, "Zero amount");
        uint64 newOrderId = orderBook.nextOrderId++;
        OrderData memory orderData = LibOrder.encodeWithdrawalOrder(
            orderParams,
            newOrderId,
            blockTimestamp,
            withdrawAccount
        );
        _appendOrder(orderBook, orderData);
        emit IOrderBook.NewWithdrawalOrder(
            withdrawAccount,
            newOrderId,
            orderParams
        );
    }

    function fillPositionOrder(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        uint64 orderId,
        uint256 blockTimestamp
    ) external returns (uint256 tradingPrice) {
        require(orderBook.orders.contains(orderId), "No such orderId");
        OrderData memory orderData = orderBook.orderData[orderId];
        _removeOrder(orderBook, orderData);
        require(
            orderData.orderType == OrderType.PositionOrder,
            "Order type mismatch"
        );
        PositionOrderParams memory orderParams = LibOrder.decodePositionOrder(
            orderData
        );
        uint256 deadline = MathUpgradeable.min(
            orderData.placeOrderTime +
                _positionOrderTimeout(configTable, orderParams),
            orderParams.expiration
        );
        require(blockTimestamp <= deadline, "Order expired");
        // fill
        if (LibOrder.isOpenPosition(orderParams)) {
            tradingPrice = fillOpenPositionOrder(
                orderBook,
                configTable,
                orderParams
            );
        } else {
            tradingPrice = fillClosePositionOrder(
                orderBook,
                orderParams,
                orderId
            );
        }
        // price check
        // open,long      0,0   0,1   1,1   1,0
        // limitOrder     <=    >=    <=    >=
        // triggerOrder   >=    <=    >=    <=
        bool isLong = _isMarketLong(orderBook, orderParams.marketId);
        bool isLess = (isLong == LibOrder.isOpenPosition(orderParams));
        if (LibOrder.isTriggerOrder(orderParams)) {
            isLess = !isLess;
        }
        if (isLess) {
            require(tradingPrice <= orderParams.limitPrice, "limitPrice");
        } else {
            require(tradingPrice >= orderParams.limitPrice, "limitPrice");
        }
        emit IOrderBook.FillOrder(orderData.account, orderId, orderData);
    }

    function fillOpenPositionOrder(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        PositionOrderParams memory orderParams
    ) internal returns (uint256 tradingPrice) {
        // auto deposit
        if (
            orderParams.collateralToken != address(0) &&
            orderParams.collateralAmount > 0
        ) {
            // deposit collateral
            _transferOut(
                orderBook,
                configTable,
                orderParams.collateralToken,
                address(orderBook.mux3Facet),
                orderParams.collateralAmount,
                false // unwrap eth
            );
            IPositionAccount(orderBook.mux3Facet).deposit(
                orderParams.positionId,
                orderParams.collateralToken,
                orderParams.collateralAmount
            );
        }
        // open
        tradingPrice = ITrade(orderBook.mux3Facet).openPosition(
            orderParams.positionId,
            orderParams.marketId,
            orderParams.size
        );
        // tp/sl strategy
        if (orderParams.tpPriceDiff > 0 || orderParams.slPriceDiff > 0) {
            // TODO: tp/sl strategy not implemented yet
            // _placeTpslOrders(orderBook, orderParams, blockTimestamp);
        }
    }

    function fillClosePositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint64 orderId
    ) internal returns (uint256 tradingPrice) {
        // close
        tradingPrice = ITrade(orderBook.mux3Facet).closePosition(
            orderParams.positionId,
            orderParams.marketId,
            orderParams.size
        );
        // auto withdraw
        if (
            orderParams.collateralToken != address(0) &&
            orderParams.collateralAmount > 0
        ) {
            IPositionAccount(orderBook.mux3Facet).withdraw(
                orderParams.positionId,
                orderParams.collateralToken,
                orderParams.collateralAmount
                // TODO: check isUnwrapWeth
            );
        }
        // tp/sl strategy
        // an order may or may not have associated tp/sl orders. delete them unconditionally
        orderBook.tpslOrders[orderParams.positionId].remove(uint256(orderId));
        // is the position completely closed
        if (_isPositionAccountFullyClosed(orderBook, orderParams.positionId)) {
            // auto withdraw
            if (LibOrder.isWithdrawIfEmpty(orderParams)) {
                IPositionAccount(orderBook.mux3Facet).withdrawAll(
                    orderParams.positionId
                );
            }
        }
        if (
            _isPositionAccountMarketFullyClosed(
                orderBook,
                orderParams.positionId,
                orderParams.marketId
            )
        ) {
            // cancel activated tp/sl orders
            // TODO
            // cancelActivatedTpslOrders(orderBook, orderParams.subAccountId);
        }
    }

    function liquidatePosition(
        OrderBookStorage storage orderBook,
        bytes32 positionId,
        bytes32 marketId
    ) external returns (uint256 tradingPrice) {
        // close
        tradingPrice = ITrade(orderBook.mux3Facet).liquidatePosition(
            positionId,
            marketId
        );

        // about auto withdraw (check closePosition for details):
        // we really do not know if we need to auto-withdraw or not.
        // thus we leave the collateral in the subAccount.

        // cancel activated tp/sl orders
        // TODO
        // cancelActivatedTpslOrders(orderBook, orderParams.subAccountId);
    }

    function setInitialLeverage(
        OrderBookStorage storage orderBook,
        bytes32 positionId,
        bytes32 marketId,
        uint256 initialLeverage
    ) external {
        require(initialLeverage > 0, "initialLeverage must be greater than 0");
        IPositionAccount(orderBook.mux3Facet).setInitialLeverage(
            positionId,
            marketId,
            initialLeverage
        );
    }

    /**
     * @dev check if position account is closed
     */
    function _isPositionAccountFullyClosed(
        OrderBookStorage storage orderBook,
        bytes32 positionId
    ) internal view returns (bool) {
        PositionReader[] memory positions = IFacetReader(orderBook.mux3Facet)
            .listAccountPositions(positionId);
        for (uint256 i = 0; i < positions.length; i++) {
            PositionPoolReader[] memory positionForPool = positions[i].pools;
            for (uint256 j = 0; j < positionForPool.length; j++) {
                if (positionForPool[j].size != 0) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @dev check if sepecific market position is closed in a position account
     */
    function _isPositionAccountMarketFullyClosed(
        OrderBookStorage storage orderBook,
        bytes32 positionId,
        bytes32 marketId
    ) internal view returns (bool) {
        PositionReader[] memory positions = IFacetReader(orderBook.mux3Facet)
            .listAccountPositions(positionId);
        for (uint256 i = 0; i < positions.length; i++) {
            PositionPoolReader[] memory positionForPool = positions[i].pools;
            for (uint256 j = 0; j < positionForPool.length; j++) {
                if (positionForPool[j].size != 0) {
                    if (positions[i].marketId == marketId) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    // function fillAdlOrder(
    //     OrderBookStorage storage orderBook,
    //     AdlOrderParams memory orderParams,
    //     uint96 tradingPrice,
    //     uint96[] memory markPrices
    // ) external returns (uint96 retTradingPrice) {
    //     // pre-check
    //     {
    //         uint96 markPrice = markPrices[orderParams.subAccountId.assetId()];
    //         require(
    //             IDegenPool(orderBook.pool).isDeleverageAllowed(
    //                 orderParams.subAccountId,
    //                 markPrice
    //             ),
    //             "ADL is not allowed"
    //         );
    //     }
    //     // fill
    //     {
    //         uint96 fillAmount = orderParams.size;
    //         tradingPrice = IDegenPool(orderBook.pool).closePosition(
    //             orderParams.subAccountId,
    //             fillAmount,
    //             tradingPrice,
    //             orderParams.profitTokenId,
    //             markPrices
    //         );
    //     }
    //     // price check
    //     {
    //         bool isLess = !orderParams.subAccountId.isLong();
    //         if (isLess) {
    //             require(tradingPrice <= orderParams.price, "limitPrice");
    //         } else {
    //             require(tradingPrice >= orderParams.price, "limitPrice");
    //         }
    //     }
    //     // is the position completely closed
    //     (uint96 collateral, uint96 size, , , ) = IDegenPool(orderBook.pool)
    //         .getSubAccount(orderParams.subAccountId);
    //     if (size == 0) {
    //         // auto withdraw
    //         if (collateral > 0) {
    //             IDegenPool(orderBook.pool).withdrawAllCollateral(
    //                 orderParams.subAccountId
    //             );
    //         }
    //         // cancel activated tp/sl orders
    //         cancelActivatedTpslOrders(orderBook, orderParams.subAccountId);
    //     }
    //     emit IOrderBook.FillAdlOrder(orderParams.subAccountId.owner(), orderParams);
    //     return tradingPrice;
    // }
    // function _placeTpslOrders(
    //     OrderBookStorage storage orderBook,
    //     PositionOrderParams memory orderParams,
    //     uint256 blockTimestamp
    // ) private {
    //     if (orderParams.tpPrice > 0 || orderParams.slPrice > 0) {
    //         _validateAssets(
    //             orderBook,
    //             orderParams.tpslProfitTokenId,
    //             ASSET_IS_STABLE | ASSET_IS_ENABLED,
    //             0
    //         );
    //     }
    //     if (orderParams.tpPrice > 0) {
    //         uint8 flags = LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY;
    //         uint8 assetId = orderParams.subAccountId.assetId();
    //         uint32 minProfitTime = IDegenPool(orderBook.pool)
    //             .getAssetParameter(assetId, LibConfigKeys.MIN_PROFIT_TIME)
    //             .toUint32();
    //         if (minProfitTime > 0) {
    //             flags |= LibOrder.POSITION_SHOULD_REACH_MIN_PROFIT;
    //         }
    //         uint64 orderId = _appendPositionOrder(
    //             orderBook,
    //             PositionOrderParams({
    //                 subAccountId: orderParams.subAccountId,
    //                 collateral: 0, // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
    //                 size: orderParams.size,
    //                 price: orderParams.tpPrice,
    //                 tpPrice: 0,
    //                 slPrice: 0,
    //                 expiration: orderParams.tpslExpiration,
    //                 tpslExpiration: 0,
    //                 profitTokenId: orderParams.tpslProfitTokenId,
    //                 tpslProfitTokenId: 0,
    //                 flags: flags
    //             }),
    //             blockTimestamp
    //         );
    //         orderBook.tpslOrders[orderParams.subAccountId].add(
    //             uint256(orderId)
    //         );
    //         require(
    //             orderBook.tpslOrders[orderParams.subAccountId].length() <=
    //                 MAX_TP_SL_ORDERS,
    //             "Too Many TP/SL Orders"
    //         );
    //     }
    //     if (orderParams.slPrice > 0) {
    //         uint64 orderId = _appendPositionOrder(
    //             orderBook,
    //             PositionOrderParams({
    //                 subAccountId: orderParams.subAccountId,
    //                 collateral: 0, // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
    //                 size: orderParams.size,
    //                 price: orderParams.slPrice,
    //                 tpPrice: 0,
    //                 slPrice: 0,
    //                 expiration: orderParams.tpslExpiration,
    //                 tpslExpiration: 0,
    //                 profitTokenId: orderParams.tpslProfitTokenId,
    //                 tpslProfitTokenId: 0,
    //                 flags: LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY |
    //                     LibOrder.POSITION_TRIGGER_ORDER
    //             }),
    //             blockTimestamp
    //         );
    //         orderBook.tpslOrders[orderParams.subAccountId].add(
    //             uint256(orderId)
    //         );
    //         require(
    //             orderBook.tpslOrders[orderParams.subAccountId].length() <=
    //                 MAX_TP_SL_ORDERS,
    //             "Too Many TP/SL Orders"
    //         );
    //     }
    // }
    function cancelOrder(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        uint64 orderId,
        uint256 blockTimestamp,
        address msgSender
    ) external {
        require(orderBook.orders.contains(orderId), "No such orderId");
        OrderData memory orderData = orderBook.orderData[orderId];
        _removeOrder(orderBook, orderData);
        // check cancel cool down
        uint256 coolDown = _cancelCoolDown(configTable);
        require(
            blockTimestamp >= orderData.placeOrderTime + coolDown,
            "Cool down"
        );
        if (orderData.orderType == OrderType.PositionOrder) {
            _cancelPositionOrder(
                orderBook,
                configTable,
                orderData,
                blockTimestamp,
                msgSender
            );
        } else if (orderData.orderType == OrderType.LiquidityOrder) {
            _cancelLiquidityOrder(orderBook, configTable, orderData, msgSender);
        } else if (orderData.orderType == OrderType.WithdrawalOrder) {
            _cancelWithdrawalOrder(
                configTable,
                orderData,
                blockTimestamp,
                msgSender
            );
        } else {
            revert();
        }
        emit IOrderBook.CancelOrder(orderData.account, orderId, orderData);
    }

    function _cancelPositionOrder(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        OrderData memory orderData,
        uint256 blockTimestamp,
        address msgSender
    ) private {
        PositionOrderParams memory orderParams = LibOrder.decodePositionOrder(
            orderData
        );
        if (_isBroker(msgSender)) {
            // broker can cancel expired order
            uint256 deadline = MathUpgradeable.min(
                orderData.placeOrderTime +
                    _positionOrderTimeout(configTable, orderParams),
                orderParams.expiration
            );
            require(blockTimestamp > deadline, "Not expired");
        } else if (_isDelegator(msgSender)) {} else {
            // account owner can cancel order
            require(msgSender == orderData.account, "Not authorized");
        }
        // return deposited collateral for open-position
        if (
            LibOrder.isOpenPosition(orderParams) &&
            orderParams.collateralToken != address(0) &&
            orderParams.collateralAmount > 0
        ) {
            _transferOut(
                orderBook,
                configTable,
                orderParams.collateralToken,
                orderData.account,
                orderParams.collateralAmount,
                LibOrder.isUnwrapWeth(orderParams)
            );
        }
        // tp/sl strategy
        // an order may or may not have associated tp/sl orders. delete them unconditionally
        orderBook.tpslOrders[orderParams.positionId].remove(
            uint256(orderData.id)
        );
    }

    function _cancelLiquidityOrder(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        OrderData memory orderData,
        address msgSender
    ) private {
        require(msgSender == orderData.account, "Not authorized");
        LiquidityOrderParams memory orderParams = LibOrder.decodeLiquidityOrder(
            orderData
        );
        if (orderParams.isAdding) {
            address collateralAddress = ICollateralPool(orderParams.poolAddress)
                .collateralToken();
            _transferOut(
                orderBook,
                configTable,
                collateralAddress,
                orderData.account,
                orderParams.rawAmount,
                orderParams.isUnwrapWeth
            );
        } else {
            _transferOut(
                orderBook,
                configTable,
                orderParams.poolAddress,
                orderData.account,
                orderParams.rawAmount,
                false // unwrap eth
            );
        }
    }

    function _cancelWithdrawalOrder(
        mapping(bytes32 => bytes32) storage configTable,
        OrderData memory orderData,
        uint256 blockTimestamp,
        address msgSender
    ) private view {
        if (_isBroker(msgSender)) {
            uint256 deadline = orderData.placeOrderTime +
                _withdrawalOrderTimeout(configTable);
            require(blockTimestamp > deadline, "Not expired");
        } else {
            require(msgSender == orderData.account, "Not authorized");
        }
    }

    function _appendPositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams, // NOTE: id, placeOrderTime, expire10s will be ignored
        uint256 blockTimestamp
    ) private returns (uint64 newOrderId) {
        (address positionAccount, ) = LibCodec.decodePositionId(
            orderParams.positionId
        );
        newOrderId = orderBook.nextOrderId++;
        OrderData memory orderData = LibOrder.encodePositionOrder(
            orderParams,
            newOrderId,
            positionAccount,
            blockTimestamp
        );
        _appendOrder(orderBook, orderData);
        emit IOrderBook.NewPositionOrder(
            positionAccount,
            newOrderId,
            orderParams
        );
    }

    function depositCollateral(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount
    ) internal {
        require(collateralAmount != 0, "Zero collateral");
        _transferIn(orderBook, collateralToken, collateralAmount);
        _transferOut(
            orderBook,
            configTable,
            collateralToken,
            address(orderBook.mux3Facet),
            collateralAmount,
            false
        );
        IPositionAccount(orderBook.mux3Facet).deposit(
            positionId,
            collateralToken,
            collateralAmount
        );
    }

    function _transferIn(
        OrderBookStorage storage orderBook,
        address tokenAddress,
        uint256 rawAmount
    ) internal {
        uint256 oldBalance = orderBook.previousTokenBalance[tokenAddress];
        uint256 newBalance = IERC20Upgradeable(tokenAddress).balanceOf(
            address(this)
        );
        require(newBalance >= oldBalance, "Token balance decreased");
        uint256 realRawAmount = newBalance - oldBalance;
        require(realRawAmount >= rawAmount, "Token balance not enough");
        orderBook.previousTokenBalance[tokenAddress] = newBalance;
    }

    function _transferOut(
        OrderBookStorage storage orderBook,
        mapping(bytes32 => bytes32) storage configTable,
        address tokenAddress,
        address recipient,
        uint256 rawAmount,
        bool isUnwrapWeth
    ) internal {
        if (tokenAddress == address(orderBook.weth) && isUnwrapWeth) {
            // try to send eth
            IWETH9(orderBook.weth).withdraw(rawAmount);
            uint256 gasLimit = _withdrawGasLimit(configTable);
            (bool success, ) = recipient.call{
                value: rawAmount,
                gas: gasLimit
            }("");
            if (success) {
                return;
            }
            // wrap and send WETH
            IWETH9(orderBook.weth).deposit{ value: rawAmount }();
            IWETH9(orderBook.weth).transfer(recipient, rawAmount);
        } else {
            IERC20Upgradeable(tokenAddress).safeTransfer(recipient, rawAmount);
        }
        orderBook.previousTokenBalance[tokenAddress] = IERC20Upgradeable(
            tokenAddress
        ).balanceOf(address(this));
    }

    function _validateMarketId(
        OrderBookStorage storage orderBook,
        bytes32 marketId
    ) private view {
        BackedPoolState[] memory pools = IFacetReader(orderBook.mux3Facet)
            .listMarketPools(marketId);
        require(pools.length > 0, "Invalid marketId");
    }

    function _validateCollateral(
        OrderBookStorage storage orderBook,
        address tokenAddress
    ) private view {
        (bool enabled, ) = IFacetReader(orderBook.mux3Facet).getCollateralToken(
            tokenAddress
        );
        require(enabled, "Invalid collateralToken");
    }

    function _validatePool(
        OrderBookStorage storage orderBook,
        address poolAddress
    ) private view {
        bool enabled = IFacetReader(orderBook.mux3Facet).getCollateralPool(
            poolAddress
        );
        require(enabled, "Invalid pool");
    }

    function _isBroker(address msgSender) private view returns (bool) {
        return
            IAccessControlUpgradeable(address(this)).hasRole(
                BROKER_ROLE,
                msgSender
            );
    }

    function _isDelegator(address msgSender) private view returns (bool) {
        return
            IAccessControlUpgradeable(address(this)).hasRole(
                DELEGATOR_ROLE,
                msgSender
            );
    }

    function _positionOrderTimeout(
        mapping(bytes32 => bytes32) storage configTable,
        PositionOrderParams memory orderParams
    ) private view returns (uint256) {
        return
            LibOrder.isMarketOrder(orderParams)
                ? configTable.getUint256(MCO_MARKET_ORDER_TIMEOUT)
                : configTable.getUint256(MCO_LIMIT_ORDER_TIMEOUT);
    }

    function _withdrawalOrderTimeout(
        mapping(bytes32 => bytes32) storage configTable
    ) private view returns (uint256) {
        return configTable.getUint256(MCO_MARKET_ORDER_TIMEOUT);
    }

    function _cancelCoolDown(
        mapping(bytes32 => bytes32) storage configTable
    ) private view returns (uint256) {
        return configTable.getUint256(MCO_CANCEL_COOL_DOWN);
    }

    function _lotSize(
        OrderBookStorage storage orderBook,
        bytes32 marketId
    ) private view returns (uint256) {
        return
            IFacetReader(orderBook.mux3Facet)
                .marketConfigValue(marketId, MM_LOT_SIZE)
                .toUint256();
    }

    function _liquidityLockPeriod(
        mapping(bytes32 => bytes32) storage configTable
    ) private view returns (uint256) {
        return configTable.getUint256(MCO_LIQUIDITY_LOCK_PERIOD);
    }

    function _isMarketLong(
        OrderBookStorage storage orderBook,
        bytes32 marketId
    ) private view returns (bool) {
        (, bool isLong) = IFacetReader(orderBook.mux3Facet).marketState(
            marketId
        );
        return isLong;
    }

    function _withdrawGasLimit(
        mapping(bytes32 => bytes32) storage configTable
    ) private view returns (uint256 gasLimit) {
        gasLimit = configTable.getUint256(MCO_UNWRAP_WETH_GAS_LIMIT);
        if (gasLimit == 0) {
            return 50_000;
        }
    }

    function _collateralToWad(
        OrderBookStorage storage orderBook,
        address collateralToken,
        uint256 rawAmount
    ) internal view returns (uint256) {
        (bool enabled, uint8 decimals) = IFacetReader(orderBook.mux3Facet)
            .getCollateralToken(collateralToken);
        require(enabled, "Collateral token not enabled");
        if (decimals <= 18) {
            return rawAmount * (10 ** (18 - decimals));
        } else {
            return rawAmount / (10 ** (decimals - 18));
        }
    }

    function _collateralToRaw(
        OrderBookStorage storage orderBook,
        address collateralToken,
        uint256 wadAmount
    ) internal view returns (uint256) {
        (bool enabled, uint8 decimals) = IFacetReader(orderBook.mux3Facet)
            .getCollateralToken(collateralToken);
        require(enabled, "Collateral token not enabled");
        if (decimals <= 18) {
            return wadAmount / 10 ** (18 - decimals);
        } else {
            return wadAmount * 10 ** (decimals - 18);
        }
    }
}
