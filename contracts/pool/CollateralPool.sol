// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../libraries/LibConfigMap.sol";
import "../interfaces/ICollateralPool.sol";
import "../interfaces/IBorrowingRate.sol";
import "../interfaces/IErrors.sol";
import "../interfaces/IFeeDistributor.sol";
import "../libraries/LibExpBorrowingRate.sol";
import "../libraries/LibTypeCast.sol";
import "./CollateralPoolToken.sol";
import "./CollateralPoolStore.sol";
import "./CollateralPoolComputed.sol";

import "hardhat/console.sol";

// TODO: delegateGuard
contract CollateralPool is
    CollateralPoolToken,
    CollateralPoolStore,
    CollateralPoolComputed,
    ICollateralPool,
    IErrors
{
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
        require(
            msg.sender == address(_orderBook),
            UnauthorizedCaller(msg.sender)
        );
        _;
    }

    constructor(address core, address orderBook) {
        _core = core;
        _orderBook = orderBook;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address collateralToken_
    ) external initializer {
        require(
            collateralToken_ != address(0),
            InvalidAddress(collateralToken_)
        );
        __CollateralPoolToken_init(name_, symbol_);
        __CollateralPoolStore_init(collateralToken_);
    }

    function collateralToken() external view returns (address) {
        return _collateralToken;
    }

    function liquidityBalances()
        external
        view
        returns (address[] memory tokens, uint256[] memory balances)
    {
        tokens = IFacetReader(_core).listCollateralTokens();
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = _liquidityBalances[tokens[i]];
        }
    }

    function markets() external view returns (bytes32[] memory) {
        return _marketIds.values();
    }

    function marketState(
        bytes32 marketId
    ) external view returns (MarketState memory) {
        return _marketStates[marketId];
    }

    function marketStates()
        external
        view
        returns (bytes32[] memory marketIds, MarketState[] memory states)
    {
        marketIds = _marketIds.values();
        states = new MarketState[](marketIds.length);
        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];
            states[i] = _marketStates[marketId];
        }
    }

    function marketConfigs(
        bytes32[] memory keyPrefixes
    )
        external
        view
        returns (bytes32[] memory marketIds, bytes32[][] memory values)
    {
        marketIds = _marketIds.values();
        values = new bytes32[][](marketIds.length);
        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];
            values[i] = new bytes32[](keyPrefixes.length);
            for (uint256 j = 0; j < keyPrefixes.length; j++) {
                bytes32 key = keccak256(
                    abi.encodePacked(keyPrefixes[j], marketId)
                );
                values[i][j] = _configTable.getBytes32(key);
            }
        }
    }

    function borrowingFeeRateApy(
        bytes32 marketId
    ) public view returns (uint256 feeRateApy) {
        IBorrowingRate.Global memory globalFr;
        globalFr.baseApy = _borrowingBaseApy();
        IBorrowingRate.AllocatePool memory poolFr = makeBorrowingContext(
            marketId
        );
        int256 fr = LibExpBorrowingRate.getBorrowingRate2(globalFr, poolFr);
        return fr.toUint256();
    }

    /**
     * @dev an AUM that can be used on chain. it uses on-chain prices and should be similar to _aumUsd
     *      which is used in addLiquidity/removeLiquidity.
     *
     *      this function MUST NOT be used in MUX3 contracts. other contacts can use this value to estimate
     *      the value of LP token.
     */
    function estimatedAumUsd() public view returns (uint256) {
        // TODO: use on-chain oracle price instead
        return _aumUsd();
    }

    function setMarket(bytes32 marketId, bool isLong) external onlyCore {
        require(!_marketIds.contains(marketId), MarketAlreadyExists(marketId));
        require(_marketIds.add(marketId), ArrayAppendFailed());
        _marketStates[marketId].isLong = isLong;
    }

    function setConfig(bytes32 key, bytes32 value) external onlyCore {
        _configTable.setBytes32(key, value);
        emit SetConfig(key, value);
    }

    function configValue(bytes32 key) external view returns (bytes32) {
        return _configTable.getBytes32(key);
    }

    function openPosition(
        bytes32 marketId,
        uint256 size
    ) external override onlyCore {
        MarketState storage data = _marketStates[marketId];
        uint256 marketPrice = IFacetReader(_core).priceOf(
            _marketOracleId(marketId)
        );
        require(marketPrice > 0, "price <= 0");
        uint256 nextTotalSize = data.totalSize + size;
        data.averageEntryPrice =
            (data.averageEntryPrice * data.totalSize + marketPrice * size) /
            nextTotalSize;
        data.totalSize = nextTotalSize;
        emit OpenPosition(
            marketId,
            size,
            data.averageEntryPrice,
            data.totalSize
        );
    }

    function closePosition(
        bytes32 marketId,
        uint256 size,
        uint256 entryPrice
    ) external override onlyCore {
        MarketState storage data = _marketStates[marketId];
        require(size <= data.totalSize, "Deallocate > pool size");
        uint256 newSize = data.totalSize - size;
        if (newSize > 0) {
            data.averageEntryPrice =
                (data.averageEntryPrice * data.totalSize - entryPrice * size) /
                newSize;
        } else {
            data.averageEntryPrice = 0;
        }
        data.totalSize = newSize;
        emit ClosePosition(marketId, size, data.totalSize);
    }

    /**
     * @dev a trader takes profit. the pool pays the profit to the market.
     */
    function realizeProfit(
        uint256 pnlUsd
    ) external onlyCore returns (address token, uint256 wad) {
        token = _collateralToken;
        uint256 collateralPrice = IFacetReader(_core).priceOf(token);
        wad = (pnlUsd * 1e18) / collateralPrice;
        uint256 raw = _toRaw(token, wad);
        wad = _toWad(token, raw); // re-calculate wad to avoid precision loss
        require(
            wad <= _liquidityBalances[token],
            InsufficientLiquidity(wad, _liquidityBalances[token])
        );
        _liquidityBalances[token] -= wad;
        emit LiquidityBalanceOut(token, collateralPrice, wad);
        IERC20Upgradeable(_collateralToken).safeTransfer(address(_core), raw);
    }

    /**
     * @dev a trader realize loss
     *
     *      note: the received token might not the collateral token.
     *      note: core should send tokens to this contract.
     */
    function realizeLoss(address token, uint256 rawAmount) external onlyCore {
        uint256 wad = _toWad(token, rawAmount);
        _liquidityBalances[token] += wad;
        uint256 collateralPrice = IFacetReader(_core).priceOf(token);
        emit LiquidityBalanceIn(token, collateralPrice, wad);
    }

    /**
     * @dev  send fees
     *
     *      note: the received token might not the collateral token.
     *      note: core should send fee to this contract.
     */
    function receiveFee(address token, uint256 rawAmount) external onlyCore {
        uint256 wad = _toWad(token, rawAmount);
        _liquidityBalances[token] += wad;
        uint256 collateralPrice = IFacetReader(_core).priceOf(token);
        emit LiquidityBalanceIn(token, collateralPrice, wad);
        emit ReceiveFee(token, collateralPrice, wad);
    }

    function addLiquidity(
        address account,
        uint256 rawCollateralAmount // OrderBook should transfer _collateralToken to this contract
    ) external override onlyOrderBook returns (uint256 shares) {
        require(rawCollateralAmount != 0, "rawCollateralAmount=0");
        // nav
        uint256 collateralPrice = IFacetReader(_core).priceOf(_collateralToken);
        uint256 aumUsd = _aumUsd();
        uint256 aumUsdWithoutPnl = _aumUsdWithoutPnl();
        uint256 lpPrice = _nav(aumUsd);
        // token amount
        uint256 collateralAmount = _toWad(
            _collateralToken,
            rawCollateralAmount
        );
        uint256 feeCollateral = (collateralAmount * _liqudityFeeRate()) / 1e18;
        collateralAmount -= feeCollateral;
        _liquidityBalances[_collateralToken] += collateralAmount;
        emit LiquidityBalanceIn(
            _collateralToken,
            collateralPrice,
            collateralAmount
        );
        // cap
        {
            uint256 liquidityCap = _liquidityCapUsd();
            uint256 collateralUsd = (collateralAmount * collateralPrice) / 1e18;
            require(
                aumUsdWithoutPnl + collateralUsd <= liquidityCap,
                CapacityExceeded(liquidityCap, aumUsdWithoutPnl, collateralUsd)
            );
        }
        // send tokens
        shares = (collateralAmount * collateralPrice) / lpPrice;
        _mint(account, shares);
        _distributeFee(account, collateralPrice, feeCollateral);
        emit AddLiquidity(
            account,
            _collateralToken,
            collateralPrice,
            feeCollateral,
            lpPrice,
            shares
        );
    }

    function removeLiquidity(
        address account,
        uint256 shares
    ) external override onlyOrderBook returns (uint256 rawCollateralAmount) {
        require(shares != 0, "shares = 0");
        // nav
        uint256 collateralPrice = IFacetReader(_core).priceOf(_collateralToken);
        uint256 aumUsd = _aumUsd();
        uint256 lpPrice = _nav(aumUsd);
        // token amount
        uint256 collateralAmount = (shares * lpPrice) / collateralPrice;
        require(
            collateralAmount <= _liquidityBalances[_collateralToken],
            InsufficientLiquidity(
                collateralAmount,
                _liquidityBalances[_collateralToken]
            )
        );
        _liquidityBalances[_collateralToken] -= collateralAmount;
        emit LiquidityBalanceOut(
            _collateralToken,
            collateralPrice,
            collateralAmount
        );
        uint256 feeCollateral = (collateralAmount * _liqudityFeeRate()) / 1e18;
        collateralAmount -= feeCollateral;
        // send tokens
        _burn(msg.sender, shares); // note: lp token is still in the OrderBook
        _distributeFee(account, collateralPrice, feeCollateral);
        rawCollateralAmount = _toRaw(_collateralToken, collateralAmount);
        IERC20Upgradeable(_collateralToken).safeTransfer(
            account,
            rawCollateralAmount
        );
        emit RemoveLiquidity(
            account,
            _collateralToken,
            collateralPrice,
            feeCollateral,
            lpPrice,
            shares
        );
    }

    /**
     * @dev distribute fee to fee distributor
     *
     *      note: we assume the fee is not added to _liquidityBalances
     */
    function _distributeFee(
        address lp,
        uint256 collateralPrice,
        uint256 feeCollateral // decimals = 18
    ) internal {
        emit CollectFee(_collateralToken, collateralPrice, feeCollateral);
        address feeDistributor = _feeDistributor();
        require(feeDistributor != address(0), "no feeDistributor");
        IERC20Upgradeable(_collateralToken).safeTransfer(
            feeDistributor,
            _toRaw(_collateralToken, feeCollateral)
        );
        IFeeDistributor(feeDistributor).updateLiquidityFees(
            lp,
            address(this), // poolAddress
            feeCollateral // decimals = 18
        );
    }

    /**
     * @dev anyone can update the borrowing state.
     */
    function updateMarketBorrowing(
        bytes32 marketId
    ) external returns (uint256 newCumulatedBorrowingPerUsd) {
        MarketState storage market = _marketStates[marketId];
        // interval check
        uint256 interval = IFacetReader(_core)
            .configValue(MC_BORROWING_INTERVAL)
            .toUint256();
        require(interval > 0, "MC_BORROWING_INTERVAL = 0");
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
        uint256 timespan = nextFundingTime - market.lastBorrowingUpdateTime;
        uint256 feeRateApy = borrowingFeeRateApy(marketId);
        newCumulatedBorrowingPerUsd =
            market.cumulatedBorrowingPerUsd +
            (feeRateApy * timespan) /
            (365 * 86400);
        market.cumulatedBorrowingPerUsd = newCumulatedBorrowingPerUsd;
        market.lastBorrowingUpdateTime = nextFundingTime;
        emit UpdateMarketBorrowing(
            marketId,
            feeRateApy,
            newCumulatedBorrowingPerUsd
        );
    }

    /**
     * @dev this is a short-cut helper for for borrowing rate calculation or pool allocation.
     *
     *      note: do NOT rely on this function outside MUX3 contracts. we probably modify the return value when necessary.
     */
    function makeBorrowingContext(
        bytes32 marketId
    ) public view returns (IBorrowingRate.AllocatePool memory poolFr) {
        poolFr.poolId = uint256(uint160(address(this)));
        poolFr.k = _borrowingK();
        poolFr.b = _borrowingB();
        poolFr.highPriority = _configTable.getBoolean(MCP_IS_HIGH_PRIORITY);
        poolFr.poolSizeUsd = _aumUsdWithoutPnl().toInt256();
        poolFr.reservedUsd = _reservedUsd().toInt256();
        poolFr.reserveRate = _adlReserveRate(marketId).toInt256();
    }

    function positionPnl(
        bytes32 marketId,
        uint256 size,
        uint256 entryPrice,
        uint256 marketPrice
    ) external view returns (bool hasProfit, uint256 cappedPnlUsd) {
        if (size == 0) {
            return (false, 0);
        }
        require(marketPrice > 0, "price <= 0");
        MarketState storage market = _marketStates[marketId];
        hasProfit = market.isLong
            ? marketPrice > entryPrice
            : marketPrice < entryPrice;
        uint256 priceDelta = marketPrice >= entryPrice
            ? marketPrice - entryPrice
            : entryPrice - marketPrice;
        cappedPnlUsd = (priceDelta * size) / 1e18;
        if (hasProfit) {
            uint256 maxPnlRate = _adlMaxPnlRate(marketId);
            uint256 maxPnlUsd = (size * entryPrice) / 1e18;
            maxPnlUsd = (maxPnlUsd * maxPnlRate) / 1e18;
            cappedPnlUsd = MathUpgradeable.min(cappedPnlUsd, maxPnlUsd);
        }
    }
}
