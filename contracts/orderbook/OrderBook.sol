// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IOrderBook.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/IReferralManager.sol";
import "../libraries/LibConfigMap.sol";
import "../libraries/LibOrderBook.sol";
import "../libraries/LibCodec.sol";
import "./OrderBookStore.sol";
import "./OrderBookGetter.sol";
import "./PriceProvider.sol";

contract OrderBook is OrderBookStore, ReentrancyGuardUpgradeable, OrderBookGetter, PriceProvider, IOrderBook {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    modifier whenNotPaused(OrderType orderType) {
        require(!_isOrderPaused(orderType), "Paused");
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

    receive() external payable {
        require(msg.sender == _storage.weth, "WETH");
    }

    /**
     * @dev Trader/LP can wrap ETH to OrderBook, transfer ERC20 to OrderBook, placeOrders
     *
     *      example for collateral = USDC:
     *        multicall([
     *          wrapNative(gas),
     *          depositGas(gas),
     *          transferToken(collateral),
     *          placePositionOrder(positionOrderParams),
     *        ])
     *      example for collateral = ETH:
     *        multicall([
     *          wrapNative(gas),
     *          depositGas(gas),
     *          wrapNative(collateral),
     *          placePositionOrder(positionOrderParams),
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
     * @dev Trader/LP can wrap ETH to OrderBook
     */
    function wrapNative(uint256 amount) external payable nonReentrant {
        require(amount > 0 && amount <= msg.value, "Invalid wrap amount");
        IWETH9(_storage.weth).deposit{ value: amount }();
    }

    /**
     * @dev Trader/LP can transfer ERC20 to OrderBook
     */
    function transferToken(address token, uint256 amount) external nonReentrant {
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Delegator can transfer ERC20 from Trader/LP to OrderBook
     */
    function transferTokenFrom(address from, address token, uint256 amount) external nonReentrant {
        require(_isDelegator(msg.sender), "Delegator only");
        IERC20Upgradeable(token).safeTransferFrom(from, address(this), amount);
    }

    /**
     * @dev Trader/LP should pay for gas for their orders
     *
     *      you should pay configValue(MCO_ORDER_GAS_FEE_GWEI) * 1e9 / 1e18 ETH for each order
     */
    function depositGas(uint256 amount) external payable nonReentrant {
        LibOrderBook.depositGas(_storage, amount, msg.sender);
    }

    /**
     * @dev Trader/LP can withdraw gas
     *
     *      usually your deposited gas should be consumed by your orders immediately,
     *      but if you want to withdraw it, you can call this function
     */
    function withdrawGas(uint256 amount) external nonReentrant {
        LibOrderBook.withdrawGas(_storage, amount, msg.sender);
    }

    /**
     * @notice A trader should set initial leverage at least once before open-position
     */
    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 initialLeverage
    ) external nonReentrant updateSequence {
        (address positionAccount, ) = LibCodec.decodePositionId(positionId);
        if (_isDelegator(msg.sender)) {} else {
            require(positionAccount == msg.sender, "Not authorized");
        }
        LibOrderBook.setInitialLeverage(_storage, positionId, marketId, initialLeverage);
    }

    /**
     * @notice A Trader can open/close position
     *
     *         Market order will expire after marketOrderTimeout seconds.
     *         Limit/Trigger order will expire after deadline.
     */
    function placePositionOrder(
        PositionOrderParams memory orderParams,
        bytes32 referralCode
    ) public payable nonReentrant whenNotPaused(OrderType.PositionOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(orderParams.positionId);
        if (_isDelegator(msg.sender)) {} else {
            require(positionAccount == msg.sender, "Not authorized");
        }
        // referral code
        address referralManager = _referralManager();
        if (referralCode != bytes32(0) && referralManager != address(0)) {
            IReferralManager(referralManager).setReferrerCodeFor(positionAccount, referralCode);
        }
        // place
        LibOrderBook.placePositionOrder(_storage, orderParams, _blockTimestamp());
    }

    /**
     * @notice A LP can add/remove liquidity to a CollateralPool
     *
     *         Can be filled after liquidityLockPeriod seconds.
     */
    function placeLiquidityOrder(
        LiquidityOrderParams memory orderParams
    ) external payable nonReentrant whenNotPaused(OrderType.LiquidityOrder) {
        LibOrderBook.placeLiquidityOrder(_storage, orderParams, msg.sender, _blockTimestamp());
    }

    /**
     * @notice A Trader can withdraw collateral
     *
     *         This order will expire after marketOrderTimeout seconds.
     */
    function placeWithdrawalOrder(
        WithdrawalOrderParams memory orderParams
    ) external payable nonReentrant whenNotPaused(OrderType.WithdrawalOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(orderParams.positionId);
        if (_isDelegator(msg.sender)) {} else {
            require(positionAccount == msg.sender, "Not authorized");
        }
        LibOrderBook.placeWithdrawalOrder(_storage, orderParams, _blockTimestamp());
    }

    /**
     * @notice A Trader can withdraw all collateral only when position = 0
     */
    function withdrawAllCollateral(
        WithdrawAllOrderParams memory orderParams
    ) external updateSequence nonReentrant whenNotPaused(OrderType.WithdrawalOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(orderParams.positionId);
        if (_isDelegator(msg.sender)) {} else {
            require(positionAccount == msg.sender, "Not authorized");
        }
        LibOrderBook.withdrawAllCollateral(_storage, orderParams);
    }

    /**
     * @notice A Rebalancer can rebalance pool liquidity by swap token0 for pool.collateralToken
     *
     *         msg.sender must implement IMux3RebalancerCallback.
     */
    function placeRebalanceOrder(
        RebalanceOrderParams memory orderParams
    ) external onlyRole(REBALANCER_ROLE) nonReentrant whenNotPaused(OrderType.RebalanceOrder) {
        address rebalancer = msg.sender;
        LibOrderBook.placeRebalanceOrder(_storage, rebalancer, orderParams, _blockTimestamp());
    }

    /**
     * @dev Open/close a position. called by Broker
     */
    function fillPositionOrder(
        uint64 orderId
    )
        external
        onlyRole(BROKER_ROLE)
        nonReentrant
        whenNotPaused(OrderType.PositionOrder)
        updateSequence
        returns (uint256 tradingPrice)
    {
        return LibOrderBook.fillPositionOrder(_storage, orderId, _blockTimestamp());
    }

    /**
     * @dev Add/remove liquidity. called by Broker
     */
    function fillLiquidityOrder(
        uint64 orderId
    )
        external
        onlyRole(BROKER_ROLE)
        whenNotPaused(OrderType.LiquidityOrder)
        nonReentrant
        updateSequence
        returns (uint256 outAmount)
    {
        return LibOrderBook.fillLiquidityOrder(_storage, orderId, _blockTimestamp());
    }

    /**
     * @dev Similar to fillLiquidityOrder with an add-liquidity order, but no share minted
     */
    function donateLiquidity(
        address poolAddress,
        address collateralAddress,
        uint256 rawAmount // token.decimals
    ) external updateSequence {
        LibOrderBook.donateLiquidity(_storage, poolAddress, collateralAddress, rawAmount);
    }

    /**
     * @dev Withdraw collateral. called by Broker
     */
    function fillWithdrawalOrder(
        uint64 orderId
    ) external onlyRole(BROKER_ROLE) nonReentrant whenNotPaused(OrderType.WithdrawalOrder) updateSequence {
        LibOrderBook.fillWithdrawalOrder(_storage, orderId, _blockTimestamp());
    }

    /**
     * @dev Swap token0 for pool.collateralToken of a pool. called by Broker
     */
    function fillRebalanceOrder(
        uint64 orderId
    ) external onlyRole(BROKER_ROLE) nonReentrant whenNotPaused(OrderType.RebalanceOrder) updateSequence {
        LibOrderBook.fillRebalanceOrder(_storage, orderId);
    }

    /**
     * @notice A Trader/LP can cancel an Order by orderId after a cool down period.
     *         A Broker can also cancel an Order after expiration.
     */
    function cancelOrder(uint64 orderId) external nonReentrant updateSequence {
        LibOrderBook.cancelOrder(_storage, orderId, _blockTimestamp(), msg.sender);
    }

    /**
     * @notice A Trader can deposit collateral into a PositionAccount
     */
    function depositCollateral(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount // token decimals
    ) external updateSequence nonReentrant {
        LibOrderBook.depositCollateral(_storage, positionId, collateralToken, collateralAmount);
    }

    /**
     * @dev Liquidate a position. called by Broker
     */
    function liquidate(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken,
        bool isWithdrawAll,
        bool isUnwrapWeth
    )
        external
        onlyRole(BROKER_ROLE)
        nonReentrant
        whenNotPaused(OrderType.LiquidityOrder)
        updateSequence
        returns (uint256 tradingPrice)
    {
        return
            LibOrderBook.liquidatePosition(
                _storage,
                positionId,
                marketId,
                lastConsumedToken,
                isWithdrawAll,
                isUnwrapWeth
            );
    }

    /**
     * @dev Deleverage a position. called by Broker
     */
    function fillAdlOrder(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken,
        bool isWithdrawAll,
        bool isUnwrapWeth
    )
        external
        onlyRole(BROKER_ROLE)
        nonReentrant
        whenNotPaused(OrderType.AdlOrder)
        updateSequence
        returns (uint256 tradingPrice)
    {
        return
            LibOrderBook.fillAdlOrder(_storage, positionId, marketId, lastConsumedToken, isWithdrawAll, isUnwrapWeth);
    }

    /**
     * @dev Reallocate a position from pool0 to pool1. called by Broker
     */
    function reallocate(
        bytes32 positionId,
        bytes32 marketId,
        address fromPool,
        address toPool,
        uint256 size,
        address lastConsumedToken,
        bool isUnwrapWeth
    ) external onlyRole(BROKER_ROLE) nonReentrant whenNotPaused(OrderType.PositionOrder) updateSequence {
        LibOrderBook.reallocate(
            _storage,
            positionId,
            marketId,
            fromPool,
            toPool,
            size,
            lastConsumedToken,
            isUnwrapWeth
        );
    }

    /**
     * @dev Updates the borrowing fee for a position and market,
     *      allowing LPs to collect fees even if the position remains open.
     */
    function updateBorrowingFee(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken,
        bool isUnwrapWeth
    ) external onlyRole(BROKER_ROLE) nonReentrant updateSequence {
        LibOrderBook.updateBorrowingFee(_storage, positionId, marketId, lastConsumedToken, isUnwrapWeth);
    }

    function _blockTimestamp() internal view virtual returns (uint64) {
        uint256 timestamp = block.timestamp;
        return LibTypeCast.toUint64(timestamp);
    }

    function setConfig(bytes32 key, bytes32 value) external nonReentrant updateSequence {
        _checkRole(MAINTAINER_ROLE, msg.sender);
        LibConfigMap.setBytes32(_storage.configTable, key, value);
    }
}
