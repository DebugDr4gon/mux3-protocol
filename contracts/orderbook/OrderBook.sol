// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IOrderBook.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/IReferralManager.sol";
import "../libraries/LibConfigMap.sol";
import "../libraries/LibOrderBook.sol";
import "../libraries/LibOrderBook2.sol";
import "../libraries/LibCodec.sol";
import "./OrderBookStore.sol";
import "./OrderBookGetter.sol";
import "./PriceProvider.sol";

contract OrderBook is OrderBookStore, ReentrancyGuardUpgradeable, OrderBookGetter, PriceProvider, IOrderBook {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /**
     * @notice Restricts function access when specific order type is paused
     * @param orderType The type of order to check
     */
    modifier whenNotPaused(OrderType orderType) {
        require(!_isOrderPaused(orderType), "Paused");
        _;
    }

    /**
     * @notice Updates the sequence number after function execution
     */
    modifier updateSequence() {
        _;
        unchecked {
            _storage.sequence += 1;
        }
        emit UpdateSequence(_storage.sequence);
    }

    /**
     * @notice Initializes the OrderBook contract
     * @param mux3Facet The address of the Mux3 Facet contract
     * @param weth The address of the WETH contract
     * @dev Can only be called once due to initializer modifier
     */
    function initialize(address mux3Facet, address weth) external initializer {
        __OrderBookStore_init();
        __ReentrancyGuard_init();
        _storage.mux3Facet = mux3Facet;
        _storage.weth = weth;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MAINTAINER_ROLE, msg.sender);
    }

    /**
     * @notice Allows contract to receive ETH from WETH contract only
     */
    receive() external payable {
        require(msg.sender == _storage.weth, "WETH");
    }

    /**
     * @notice Executes multiple function calls in a single transaction
     * @param proxyCalls Array of function calls to execute
     * @return results Array of return values from each call
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
     * @notice Trader/LP can wrap native ETH to WETH and WETH will stay in OrderBook for subsequent commands
     *
     *         note: wrapNative is intended to be used as part of a multicall. If it is called directly
     *               the caller would end up losing the funds.
     *         note: wrapNative is intended to be consumed in depositGas or placePositionOrder/placeLiquidityOrder.
     *               Any excess ETH sent beyond the amount parameter will be lost in the contract.
     * @param amount Amount of ETH to wrap
     * @dev Amount must be greater than 0 and less than or equal to msg.value
     */
    function wrapNative(uint256 amount) external payable nonReentrant {
        require(amount > 0 && amount <= msg.value, "Invalid wrap amount");
        IWETH9(_storage.weth).deposit{ value: amount }();
    }

    /**
     * @notice Trader/LP transfer ERC20 tokens (usually collaterals) to the OrderBook
     *
     *         note: transferToken is intended to be used as part of a multicall. If it is called directly
     *               the caller would end up losing the funds.
     *         note: transferToken is intended to be consumed in placePositionOrder/placeLiquidityOrder.
     *               Any excess tokens sent beyond the amount parameter will be lost in the contract.
     * @param token Address of the token to transfer
     * @param amount Amount of tokens to transfer
     */
    function transferToken(address token, uint256 amount) external payable nonReentrant {
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Allows Delegator to transfer tokens from Trader/LP to OrderBook
     * @param from Address to transfer tokens from
     * @param token Address of the token to transfer
     * @param amount Amount of tokens to transfer
     */
    function transferTokenFrom(address from, address token, uint256 amount) external payable nonReentrant {
        require(_isDelegator(msg.sender), "Delegator only");
        IERC20Upgradeable(token).safeTransferFrom(from, address(this), amount);
    }

    /**
     * @notice Trader/LP should pay for gas for their orders
     *         you should pay at least configValue(MCO_ORDER_GAS_FEE_GWEI) * 1e9 / 1e18 ETH for each order
     * @param amount The amount of gas to deposit
     */
    function depositGas(address account, uint256 amount) external payable nonReentrant {
        if (_isDelegator(msg.sender)) {
            // pass
        } else {
            require(account == msg.sender, "Not authorized");
        }
        LibOrderBook.depositGas(_storage, amount, account);
    }

    /**
     * @notice Trader/LP can withdraw gas
     *      usually your deposited gas should be consumed by your orders immediately,
     *      but if you want to withdraw it, you can call this function
     * @param amount The amount of gas to withdraw
     */
    function withdrawGas(address account, uint256 amount) external nonReentrant {
        if (_isDelegator(msg.sender)) {
            // although Delegator does not support withdrawGas yet, it is still safe here
        } else {
            require(account == msg.sender, "Not authorized");
        }
        LibOrderBook.withdrawGas(_storage, amount, account);
    }

    /**
     * @notice A trader should set initial leverage at least once before open-position
     * @param positionId The ID of the position
     * @param marketId The ID of the market
     * @param initialLeverage The initial leverage to set
     * @dev do not need depositGas
     */
    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 initialLeverage
    ) external payable nonReentrant updateSequence {
        (address positionAccount, ) = LibCodec.decodePositionId(positionId);
        if (_isDelegator(msg.sender)) {
            // pass
        } else {
            require(positionAccount == msg.sender, "Not authorized");
        }
        LibOrderBook.setInitialLeverage(_storage, positionId, marketId, initialLeverage);
    }

    /**
     * @notice A Trader can open/close position
     *         Market order will expire after marketOrderTimeout seconds.
     *         Limit/Trigger order will expire after deadline.
     * @param orderParams The parameters for the position order
     * @param referralCode The referral code for the position order
     * @dev depositGas required (consume gas when filled)
     */
    function placePositionOrder(
        PositionOrderParams memory orderParams,
        bytes32 referralCode
    ) public payable nonReentrant whenNotPaused(OrderType.PositionOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(orderParams.positionId);
        if (_isDelegator(msg.sender)) {
            // pass
        } else {
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
     *         Can be filled after liquidityLockPeriod seconds.
     * @param orderParams The parameters for the liquidity order
     * @dev depositGas required (consume gas when filled)
     */
    function placeLiquidityOrder(
        LiquidityOrderParams memory orderParams
    ) external payable nonReentrant whenNotPaused(OrderType.LiquidityOrder) {
        LibOrderBook2.placeLiquidityOrder(_storage, orderParams, msg.sender, _blockTimestamp());
    }

    /**
     * @notice A Trader can withdraw collateral
     *         This order will expire after marketOrderTimeout seconds.
     * @param orderParams The parameters for the withdrawal order
     * @dev depositGas required (consume gas when filled)
     */
    function placeWithdrawalOrder(
        WithdrawalOrderParams memory orderParams
    ) external payable nonReentrant whenNotPaused(OrderType.WithdrawalOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(orderParams.positionId);
        if (_isDelegator(msg.sender)) {
            // pass
        } else {
            require(positionAccount == msg.sender, "Not authorized");
        }
        LibOrderBook2.placeWithdrawalOrder(_storage, orderParams, _blockTimestamp());
    }

    /**
     * @notice A Trader can deposit collateral into a PositionAccount
     * @param positionId The ID of the position
     * @param collateralToken The address of the collateral token
     * @param collateralAmount The amount of collateral token
     * @dev do not need depositGas
     */
    function depositCollateral(
        bytes32 positionId,
        address collateralToken,
        uint256 collateralAmount // token decimals
    ) external payable updateSequence nonReentrant {
        (address positionAccount, ) = LibCodec.decodePositionId(positionId);
        if (_isDelegator(msg.sender)) {
            // pass
        } else {
            require(positionAccount == msg.sender, "Not authorized");
        }
        LibOrderBook2.depositCollateral(_storage, positionId, collateralToken, collateralAmount);
    }

    /**
     * @notice A Trader can withdraw all collateral only when position = 0
     * @param orderParams The parameters for the withdrawal order
     * @dev do not need depositGas
     */
    function withdrawAllCollateral(
        WithdrawAllOrderParams memory orderParams
    ) external updateSequence nonReentrant whenNotPaused(OrderType.WithdrawalOrder) {
        (address positionAccount, ) = LibCodec.decodePositionId(orderParams.positionId);
        if (_isDelegator(msg.sender)) {
            // pass
        } else {
            require(positionAccount == msg.sender, "Not authorized");
        }
        LibOrderBook2.withdrawAllCollateral(_storage, orderParams);
    }

    /**
     * @notice A Trader/LP can cancel an Order by orderId after a cool down period.
     *         A Broker can also cancel an Order after expiration.
     * @param orderId The ID of the order to cancel
     */
    function cancelOrder(uint64 orderId) external nonReentrant updateSequence {
        LibOrderBook.cancelOrder(_storage, orderId, _blockTimestamp(), msg.sender);
    }

    /**
     * @notice A Rebalancer can rebalance pool liquidity by swap token0 for pool.collateralToken
     *         msg.sender must implement IMux3RebalancerCallback.
     * @param orderParams The parameters for the rebalance order
     * @dev do not need depositGas
     */
    function placeRebalanceOrder(
        RebalanceOrderParams memory orderParams
    ) external onlyRole(REBALANCER_ROLE) nonReentrant whenNotPaused(OrderType.RebalanceOrder) {
        address rebalancer = msg.sender;
        LibOrderBook2.placeRebalanceOrder(_storage, rebalancer, orderParams, _blockTimestamp());
    }

    /**
     * @notice Open/close a position. called by Broker
     * @param orderId The ID of the order to fill
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
     * @notice Add/remove liquidity. called by Broker
     * @param orderId The ID of the order to fill
     * @param reallocateArgs Arguments to reallocate positions between pools to keep a more balanced utilization (optional)
     * @return outAmount The amount of output tokens
     */
    function fillLiquidityOrder(
        uint64 orderId,
        IFacetOpen.ReallocatePositionArgs[] memory reallocateArgs
    )
        external
        onlyRole(BROKER_ROLE)
        whenNotPaused(OrderType.LiquidityOrder)
        nonReentrant
        updateSequence
        returns (uint256 outAmount)
    {
        return LibOrderBook2.fillLiquidityOrder(_storage, orderId, reallocateArgs, _blockTimestamp());
    }

    /**
     * @notice Withdraw collateral. called by Broker
     * @param orderId The ID of the order to fill
     */
    function fillWithdrawalOrder(
        uint64 orderId
    ) external onlyRole(BROKER_ROLE) nonReentrant whenNotPaused(OrderType.WithdrawalOrder) updateSequence {
        LibOrderBook2.fillWithdrawalOrder(_storage, orderId, _blockTimestamp());
    }

    /**
     * @notice Swap token0 for pool.collateralToken of a pool. called by Broker
     * @param orderId The ID of the order to fill
     */
    function fillRebalanceOrder(
        uint64 orderId
    ) external onlyRole(BROKER_ROLE) nonReentrant whenNotPaused(OrderType.RebalanceOrder) updateSequence {
        LibOrderBook2.fillRebalanceOrder(_storage, orderId);
    }

    /**
     * @notice Liquidate all positions in a PositionAccount. called by Broker
     * @param positionId The ID of the position
     * @param lastConsumedToken The address of the last consumed token
     * @param isWithdrawAllIfEmpty Set false so that collaterals will remain in the position account.
     * @param isUnwrapWeth Whether to unwrap WETH
     */
    function liquidate(
        bytes32 positionId,
        address lastConsumedToken,
        bool isWithdrawAllIfEmpty,
        bool isUnwrapWeth
    ) external onlyRole(BROKER_ROLE) nonReentrant whenNotPaused(OrderType.LiquidateOrder) updateSequence {
        LibOrderBook.liquidate(_storage, positionId, lastConsumedToken, isWithdrawAllIfEmpty, isUnwrapWeth);
    }

    /**
     * @notice Deleverage a position. called by Broker
     * @param positionId The ID of the position
     * @param marketId The ID of the market
     * @param lastConsumedToken The address of the last consumed token
     * @param isWithdrawAllIfEmpty Whether to withdraw all collateral
     * @param isUnwrapWeth Whether to unwrap WETH
     * @return tradingPrice The trading price
     */
    function fillAdlOrder(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken,
        bool isWithdrawAllIfEmpty,
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
            LibOrderBook.fillAdlOrder(
                _storage,
                positionId,
                marketId,
                lastConsumedToken,
                isWithdrawAllIfEmpty,
                isUnwrapWeth
            );
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
     * @notice Updates the borrowing fee for a position and market,
     *         allowing LPs to collect fees even if the position remains open.
     * @param positionId The ID of the position
     * @param marketId The ID of the market
     * @param lastConsumedToken The address of the last consumed token
     * @param isUnwrapWeth Whether to unwrap WETH
     */
    function updateBorrowingFee(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken,
        bool isUnwrapWeth
    ) external onlyRole(BROKER_ROLE) nonReentrant updateSequence {
        LibOrderBook2.updateBorrowingFee(_storage, positionId, marketId, lastConsumedToken, isUnwrapWeth);
    }

    /**
     * @notice Similar to fillLiquidityOrder, but no share minted.
     * @param poolAddress The address of the pool
     * @param collateralAddress The address of the collateral token
     * @param rawAmount The amount of collateral token in token decimals
     * @dev Usually used to send trading fees to CollateralPool
     */
    function donateLiquidity(
        address poolAddress,
        address collateralAddress,
        uint256 rawAmount // token.decimals
    ) external updateSequence {
        require(_isFeeDonator(msg.sender), "Not authorized");
        LibOrderBook.donateLiquidity(_storage, poolAddress, collateralAddress, rawAmount);
    }

    function _blockTimestamp() internal view virtual returns (uint64) {
        uint256 timestamp = block.timestamp;
        return LibTypeCast.toUint64(timestamp);
    }

    function _isFeeDonator(address addr) internal view returns (bool) {
        if (addr == LibOrderBook._feeDistributor(_storage)) {
            // Mux3FeeDistributor is valid
            return true;
        }
        if (hasRole(FEE_DONATOR_ROLE, addr)) {
            // for future use
            return true;
        }
        return false;
    }

    function setConfig(bytes32 key, bytes32 value) external nonReentrant updateSequence {
        _checkRole(MAINTAINER_ROLE, msg.sender);
        LibConfigMap.setBytes32(_storage.configTable, key, value);
    }

    function setCallbackWhitelist(address account, bool isWhitelisted) external nonReentrant updateSequence {
        _checkRole(MAINTAINER_ROLE, msg.sender);
        _storage.callbackWhitelist[account] = isWhitelisted;
    }
}
