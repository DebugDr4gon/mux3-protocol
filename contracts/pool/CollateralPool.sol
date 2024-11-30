// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../interfaces/IBorrowingRate.sol";
import "../interfaces/ICollateralPool.sol";
import "../interfaces/ICollateralPoolEventEmitter.sol";
import "../interfaces/IErrors.sol";
import "../interfaces/IMux3FeeDistributor.sol";
import "../interfaces/IMux3RebalancerCallback.sol";
import "../libraries/LibConfigMap.sol";
import "../libraries/LibEthUnwrapper.sol";
import "../libraries/LibExpBorrowingRate.sol";
import "../libraries/LibTypeCast.sol";
import "./CollateralPoolToken.sol";
import "./CollateralPoolStore.sol";
import "./CollateralPoolComputed.sol";

contract CollateralPool is CollateralPoolToken, CollateralPoolStore, CollateralPoolComputed, ICollateralPool, IErrors {
    using LibConfigMap for mapping(bytes32 => bytes32);
    using LibTypeCast for int256;
    using LibTypeCast for uint256;
    using LibTypeCast for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    modifier onlyCore() {
        require(msg.sender == address(_core), UnauthorizedCaller(msg.sender));
        _;
    }

    modifier onlyOrderBook() {
        require(msg.sender == address(_orderBook), UnauthorizedCaller(msg.sender));
        _;
    }

    constructor(address core_, address orderBook_, address weth_, address eventEmitter_) {
        _core = core_;
        _orderBook = orderBook_;
        _weth = weth_;
        _eventEmitter = eventEmitter_;
    }

    function initialize(string memory name_, string memory symbol_, address collateralToken_) external initializer {
        require(collateralToken_ != address(0), InvalidAddress(collateralToken_));
        __CollateralPoolToken_init(name_, symbol_);
        __CollateralPoolStore_init(collateralToken_);
    }

    // for removeLiquidity
    receive() external payable {
        require(msg.sender == _weth, UnauthorizedCaller(msg.sender));
    }

    function collateralToken() external view returns (address) {
        return _collateralToken;
    }

    function liquidityBalances() external view returns (address[] memory tokens, uint256[] memory balances) {
        tokens = IFacetReader(_core).listCollateralTokens();
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = _liquidityBalances[tokens[i]];
        }
    }

    function markets() external view returns (bytes32[] memory) {
        return _marketIds.values();
    }

    function marketState(bytes32 marketId) external view returns (MarketState memory) {
        return _marketStates[marketId];
    }

    function marketStates() external view returns (bytes32[] memory marketIds, MarketState[] memory states) {
        marketIds = _marketIds.values();
        states = new MarketState[](marketIds.length);
        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];
            states[i] = _marketStates[marketId];
        }
    }

    function marketConfigs(
        bytes32[] memory keyPrefixes
    ) external view returns (bytes32[] memory marketIds, bytes32[][] memory values) {
        marketIds = _marketIds.values();
        values = new bytes32[][](marketIds.length);
        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];
            values[i] = new bytes32[](keyPrefixes.length);
            for (uint256 j = 0; j < keyPrefixes.length; j++) {
                bytes32 key = keccak256(abi.encodePacked(keyPrefixes[j], marketId));
                values[i][j] = _configTable.getBytes32(key);
            }
        }
    }

    function borrowingFeeRateApy(bytes32 marketId) public view returns (uint256 feeRateApy) {
        IBorrowingRate.Global memory globalFr;
        globalFr.baseApy = _borrowingBaseApy();
        IBorrowingRate.AllocatePool memory poolFr = makeBorrowingContext(marketId);
        int256 fr = LibExpBorrowingRate.getBorrowingRate2(globalFr, poolFr);
        return fr.toUint256();
    }

    function setMarket(bytes32 marketId, bool isLong) external onlyCore {
        require(!_marketIds.contains(marketId), MarketAlreadyExist(marketId));
        require(_marketIds.add(marketId), ArrayAppendFailed());
        _marketStates[marketId].isLong = isLong;
    }

    function setConfig(bytes32 key, bytes32 value) external onlyCore {
        _configTable.setBytes32(key, value);
        ICollateralPoolEventEmitter(_eventEmitter).emitSetConfig(key, value);
    }

    /**
     * @dev Modifying ERC20 name is not a common practice. If we really need it, this is the only way.
     */
    function name() public view override returns (string memory) {
        string memory overrideName = _configTable.getString(MCP_TOKEN_NAME);
        return bytes(overrideName).length > 0 ? overrideName : super.name();
    }

    /**
     * @dev Modifying ERC20 symbols is not a common practice. If we really need it, this is the only way.
     */
    function symbol() public view override returns (string memory) {
        string memory overrideSymbol = _configTable.getString(MCP_TOKEN_SYMBOL);
        return bytes(overrideSymbol).length > 0 ? overrideSymbol : super.symbol();
    }

    function configValue(bytes32 key) external view returns (bytes32) {
        return _configTable.getBytes32(key);
    }

    function getAumUsdWithoutPnl() external view returns (uint256) {
        return _aumUsdWithoutPnl();
    }

    function getAumUsd() external view returns (uint256) {
        return _aumUsd();
    }

    function openPosition(bytes32 marketId, uint256 size) external override onlyCore {
        MarketState storage data = _marketStates[marketId];
        uint256 marketPrice = IFacetReader(_core).priceOf(_marketOracleId(marketId));
        uint256 nextTotalSize = data.totalSize + size;
        data.averageEntryPrice = (data.averageEntryPrice * data.totalSize + marketPrice * size) / nextTotalSize;
        data.totalSize = nextTotalSize;
        ICollateralPoolEventEmitter(_eventEmitter).emitOpenPosition(
            marketId,
            size,
            data.averageEntryPrice,
            data.totalSize
        );
    }

    function closePosition(bytes32 marketId, uint256 size, uint256 entryPrice) external override onlyCore {
        MarketState storage data = _marketStates[marketId];
        require(size <= data.totalSize, AllocationPositionMismatch(size, data.totalSize));
        uint256 newSize = data.totalSize - size;
        if (newSize > 0) {
            // in order to keep nav
            data.averageEntryPrice = (data.averageEntryPrice * data.totalSize - entryPrice * size) / newSize;
        } else {
            data.averageEntryPrice = 0;
        }
        data.totalSize = newSize;
        ICollateralPoolEventEmitter(_eventEmitter).emitClosePosition(marketId, size, data.totalSize);
    }

    /**
     * @dev A trader takes profit. the pool pays the profit to the market.
     */
    function realizeProfit(
        uint256 pnlUsd
    )
        external
        onlyCore
        returns (
            address token,
            uint256 wad // 1e18
        )
    {
        token = _collateralToken;
        uint256 collateralPrice = IFacetReader(_core).priceOf(token);
        wad = (pnlUsd * 1e18) / collateralPrice;
        uint256 raw = _toRaw(token, wad);
        wad = _toWad(token, raw); // re-calculate wad to avoid precision loss
        require(wad <= _liquidityBalances[token], InsufficientLiquidity(wad, _liquidityBalances[token]));
        _liquidityBalances[token] -= wad;
        ICollateralPoolEventEmitter(_eventEmitter).emitLiquidityBalanceOut(token, collateralPrice, wad);
        IERC20Upgradeable(token).safeTransfer(address(_core), raw);
    }

    /**
     * @dev A trader realize loss
     *
     *      note: the received token might not the collateral token.
     *      note: core should send tokens to this contract.
     */
    function realizeLoss(
        address token,
        uint256 rawAmount // token decimals
    ) external onlyCore {
        uint256 wad = _toWad(token, rawAmount);
        _liquidityBalances[token] += wad;
        uint256 collateralPrice = IFacetReader(_core).priceOf(token);
        ICollateralPoolEventEmitter(_eventEmitter).emitLiquidityBalanceIn(token, collateralPrice, wad);
    }

    /**
     * @dev Get fees from FeeDistributor => OrderBook => CollateralPool
     *
     *      note: the received token might not the collateral token.
     *      note: orderBook should send fee to this contract.
     */
    function receiveFee(address token, uint256 rawAmount) external onlyOrderBook {
        uint256 wad = _toWad(token, rawAmount);
        _liquidityBalances[token] += wad;
        uint256 collateralPrice = IFacetReader(_core).priceOf(token);
        ICollateralPoolEventEmitter(_eventEmitter).emitLiquidityBalanceIn(token, collateralPrice, wad);
        ICollateralPoolEventEmitter(_eventEmitter).emitReceiveFee(token, collateralPrice, wad);
    }

    /**
     * @dev Add liquidity to the pool and returns shares to the lp.
     *
     *      note: orderBook should transfer rawCollateralAmount to this contract
     */
    function addLiquidity(
        AddLiquidityArgs memory args
    ) external override onlyOrderBook returns (AddLiquidityResult memory result) {
        _updateAllMarketBorrowing();
        require(args.rawCollateralAmount != 0, InvalidAmount("rawCollateralAmount"));
        require(_isCollateralExist(_collateralToken), CollateralNotExist(_collateralToken));
        // nav
        uint256 collateralPrice = IFacetReader(_core).priceOf(_collateralToken);
        uint256 aumUsd = _aumUsd();
        uint256 aumUsdWithoutPnl = _aumUsdWithoutPnl(); // important: read this before add liquidity
        uint256 lpPrice = _nav(aumUsd);
        // token amount
        uint256 collateralAmount = _toWad(_collateralToken, args.rawCollateralAmount);
        uint256 liquidityFeeCollateral = (collateralAmount * _liquidityFeeRate()) / 1e18;
        require(
            collateralAmount >= liquidityFeeCollateral,
            InsufficientCollateral(collateralAmount, liquidityFeeCollateral)
        );
        collateralAmount -= liquidityFeeCollateral;
        // to pool
        _liquidityBalances[_collateralToken] += collateralAmount;
        ICollateralPoolEventEmitter(_eventEmitter).emitLiquidityBalanceIn(
            _collateralToken,
            collateralPrice,
            collateralAmount
        );
        // verify
        {
            uint256 liquidityCap = _liquidityCapUsd();
            uint256 collateralUsd = (collateralAmount * collateralPrice) / 1e18;
            require(
                aumUsdWithoutPnl + collateralUsd <= liquidityCap,
                CapacityExceeded(liquidityCap, aumUsdWithoutPnl, collateralUsd)
            );
        }
        // share
        result.shares = (collateralAmount * collateralPrice) / lpPrice;
        _mint(args.account, result.shares);
        // fees
        _distributeFee(args.account, collateralPrice, liquidityFeeCollateral, args.isUnwrapWeth);
        // done
        ICollateralPoolEventEmitter(_eventEmitter).emitAddLiquidity(
            args.account,
            _collateralToken,
            collateralPrice,
            liquidityFeeCollateral,
            lpPrice,
            result.shares
        );
    }

    /**
     * @dev Remove liquidity from the pool and returns collateral tokens to the lp.
     *
     *      note: orderBook should transfer share token to this contract
     */
    function removeLiquidity(
        RemoveLiquidityArgs memory args
    ) external override onlyOrderBook returns (RemoveLiquidityResult memory result) {
        _updateAllMarketBorrowing();
        require(args.shares != 0, InvalidAmount("shares"));
        require(_isCollateralExist(_collateralToken), CollateralNotExist(_collateralToken));
        // nav
        uint256 aumUsd = _aumUsd();
        uint256 lpPrice = _nav(aumUsd);
        // from pool
        uint256 collateralPrice = IFacetReader(_core).priceOf(_collateralToken);
        uint256 collateralAmount = (args.shares * lpPrice) / collateralPrice;
        require(
            collateralAmount <= _liquidityBalances[_collateralToken],
            InsufficientLiquidity(collateralAmount, _liquidityBalances[_collateralToken])
        );
        _liquidityBalances[_collateralToken] -= collateralAmount;
        ICollateralPoolEventEmitter(_eventEmitter).emitLiquidityBalanceOut(
            _collateralToken,
            collateralPrice,
            collateralAmount
        );
        {
            uint256 removedValue = (collateralPrice * collateralAmount) / 1e18;
            if (removedValue < aumUsd) {
                aumUsd -= removedValue;
            } else {
                aumUsd = 0;
            }
        }
        // fees
        uint256 liquidityFeeCollateral = (collateralAmount * _liquidityFeeRate()) / 1e18;
        collateralAmount -= liquidityFeeCollateral;
        _distributeFee(args.account, collateralPrice, liquidityFeeCollateral, args.isUnwrapWeth);
        // send tokens to lp
        _burn(address(this), args.shares);
        result.rawCollateralAmount = _toRaw(_collateralToken, collateralAmount);
        if (_collateralToken == _weth && args.isUnwrapWeth) {
            LibEthUnwrapper.unwrap(_weth, payable(args.account), result.rawCollateralAmount);
        } else {
            IERC20Upgradeable(_collateralToken).safeTransfer(args.account, result.rawCollateralAmount);
        }
        // verify
        {
            uint256 reservedUsd = _reservedUsd();
            require(reservedUsd <= aumUsd, InsufficientLiquidity(reservedUsd, aumUsd));
        }
        ICollateralPoolEventEmitter(_eventEmitter).emitRemoveLiquidity(
            args.account,
            _collateralToken,
            collateralPrice,
            liquidityFeeCollateral,
            lpPrice,
            args.shares
        );
    }

    /**
     * @dev  Rebalance pool liquidity. Swap token0 in this pool into pool.collateralToken.
     *
     *       rebalancer must implement IMux3RebalancerCallback.
     */
    function rebalance(
        address rebalancer,
        address token0,
        uint256 rawAmount0, // token0 decimals
        uint256 maxRawAmount1, // collateralToken decimals
        bytes memory userData
    ) external override onlyOrderBook returns (uint256 rawAmount1) {
        _updateAllMarketBorrowing();
        require(rebalancer != address(0), InvalidAddress(rebalancer));
        require(token0 != _collateralToken, InvalidAddress(token0));
        require(_isCollateralExist(token0), CollateralNotExist(token0));
        require(_isCollateralExist(_collateralToken), CollateralNotExist(_collateralToken));
        uint256 price0 = IFacetReader(_core).priceOf(token0);
        uint256 price1 = IFacetReader(_core).priceOf(_collateralToken);
        // send token 0
        require(rawAmount0 != 0, InvalidAmount("rawAmount0"));
        uint256 amount0 = _toWad(token0, rawAmount0);
        require(amount0 <= _liquidityBalances[token0], InsufficientLiquidity(amount0, _liquidityBalances[token0]));
        _liquidityBalances[token0] -= amount0;
        IERC20Upgradeable(token0).safeTransfer(rebalancer, rawAmount0);
        ICollateralPoolEventEmitter(_eventEmitter).emitLiquidityBalanceOut(token0, price0, amount0);
        // expected
        uint256 expectedAmount1 = (amount0 * price0) / price1;
        uint256 expectedRawAmount1 = _toRaw(_collateralToken, expectedAmount1);
        require(expectedRawAmount1 <= maxRawAmount1, LimitPriceNotMet(expectedRawAmount1, maxRawAmount1));
        // swap. check amount 1
        {
            uint256 rawAmount1Old = IERC20Upgradeable(_collateralToken).balanceOf(address(this));
            IMux3RebalancerCallback(rebalancer).mux3RebalanceCallback(
                address(this),
                token0,
                _collateralToken,
                rawAmount0,
                expectedRawAmount1,
                userData
            );
            uint256 rawAmount1New = IERC20Upgradeable(_collateralToken).balanceOf(address(this));
            require(
                rawAmount1Old <= rawAmount1New,
                InsufficientCollateralBalance(_collateralToken, rawAmount1New, rawAmount1Old)
            ); // this is a dummy protection that never happens
            rawAmount1 = rawAmount1New - rawAmount1Old;
        }
        require(rawAmount1 >= expectedRawAmount1, LimitPriceNotMet(expectedRawAmount1, rawAmount1));
        uint256 amount1 = _toWad(_collateralToken, rawAmount1);
        _liquidityBalances[_collateralToken] += amount1;
        ICollateralPoolEventEmitter(_eventEmitter).emitLiquidityBalanceIn(_collateralToken, price1, amount1);
        ICollateralPoolEventEmitter(_eventEmitter).emitRebalance(
            rebalancer,
            token0,
            _collateralToken,
            price0,
            price1,
            amount0,
            amount1
        );
    }

    /**
     * @dev Distribute fee to fee distributor
     *
     *      note: we assume the fee is not added to _liquidityBalances
     */
    function _distributeFee(
        address lp,
        uint256 collateralPrice,
        uint256 feeCollateral, // decimals = 18
        bool isUnwrapWeth
    ) internal {
        ICollateralPoolEventEmitter(_eventEmitter).emitCollectFee(_collateralToken, collateralPrice, feeCollateral);
        address feeDistributor = _feeDistributor();
        uint256 rawFee = _toRaw(_collateralToken, feeCollateral);
        IERC20Upgradeable(_collateralToken).safeTransfer(feeDistributor, rawFee);
        IMux3FeeDistributor(feeDistributor).updateLiquidityFees(
            lp,
            address(this), // poolAddress
            _collateralToken,
            rawFee,
            isUnwrapWeth
        );
    }

    /**
     * @dev Update the borrowing state.
     */
    function updateMarketBorrowing(bytes32 marketId) external onlyCore returns (uint256 newCumulatedBorrowingPerUsd) {
        return _updateMarketBorrowing(marketId);
    }

    function _updateMarketBorrowing(bytes32 marketId) internal returns (uint256 newCumulatedBorrowingPerUsd) {
        MarketState storage market = _marketStates[marketId];
        // interval check
        uint256 interval = IFacetReader(_core).configValue(MC_BORROWING_INTERVAL).toUint256();
        require(interval > 0, EssentialConfigNotSet("MC_BORROWING_INTERVAL"));
        uint256 blockTime = block.timestamp;
        uint256 nextFundingTime = (blockTime / interval) * interval;
        if (market.lastBorrowingUpdateTime == 0) {
            // init state. just update lastFundingTime
            market.lastBorrowingUpdateTime = nextFundingTime;
            return market.cumulatedBorrowingPerUsd;
        } else if (market.lastBorrowingUpdateTime + interval >= blockTime) {
            // do nothing
            return market.cumulatedBorrowingPerUsd;
        }
        uint256 timeSpan = nextFundingTime - market.lastBorrowingUpdateTime;
        uint256 feeRateApy = borrowingFeeRateApy(marketId);
        newCumulatedBorrowingPerUsd = market.cumulatedBorrowingPerUsd + (feeRateApy * timeSpan) / (365 * 86400);
        market.cumulatedBorrowingPerUsd = newCumulatedBorrowingPerUsd;
        market.lastBorrowingUpdateTime = nextFundingTime;
        ICollateralPoolEventEmitter(_eventEmitter).emitUpdateMarketBorrowing(
            marketId,
            feeRateApy,
            newCumulatedBorrowingPerUsd
        );
    }

    function _updateAllMarketBorrowing() internal {
        uint256 marketCount = _marketIds.length();
        for (uint256 i = 0; i < marketCount; i++) {
            bytes32 marketId = _marketIds.at(i);
            _updateMarketBorrowing(marketId);
        }
    }

    /**
     * @dev This is a helper for borrowing rate calculation or pool allocation.
     *
     *      note: do NOT rely on this function outside MUX3 contracts. we probably modify the return value when necessary.
     */
    function makeBorrowingContext(bytes32 marketId) public view returns (IBorrowingRate.AllocatePool memory poolFr) {
        poolFr.poolId = uint256(uint160(address(this)));
        poolFr.k = _borrowingK();
        poolFr.b = _borrowingB();
        poolFr.poolSizeUsd = _aumUsdWithoutPnl().toInt256();
        poolFr.reservedUsd = _reservedUsd().toInt256();
        poolFr.reserveRate = _adlReserveRate(marketId).toInt256();
        poolFr.isDraining = _isDraining();
    }

    function positionPnl(
        bytes32 marketId,
        uint256 size,
        uint256 entryPrice,
        uint256 marketPrice
    ) external view returns (int256 pnlUsd, int256 cappedPnlUsd) {
        if (size == 0) {
            return (0, 0);
        }
        require(marketPrice > 0, MissingPrice(_marketOracleId(marketId)));
        MarketState storage market = _marketStates[marketId];
        int256 priceDelta = marketPrice.toInt256() - entryPrice.toInt256();
        if (!market.isLong) {
            priceDelta = -priceDelta;
        }
        pnlUsd = (priceDelta * size.toInt256()) / 1e18;
        cappedPnlUsd = pnlUsd;
        if (pnlUsd > 0) {
            // cap the trader upnl
            // note that this is not strictly identical to deleverage all positions. this is just an estimated
            //      value when the price increases dramatically.
            uint256 maxPnlRate = _adlMaxPnlRate(marketId);
            uint256 maxPnlUsd = (size * entryPrice) / 1e18;
            maxPnlUsd = (maxPnlUsd * maxPnlRate) / 1e18;
            cappedPnlUsd = MathUpgradeable.min(uint256(pnlUsd), maxPnlUsd).toInt256();
        }
    }
}
