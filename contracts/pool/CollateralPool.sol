// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../libraries/LibConfigTable.sol";
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
    using LibConfigTable for ConfigTable;
    using LibTypeCast for int256;
    using LibTypeCast for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    modifier onlyCore() {
        require(msg.sender == address(_core), UnauthorizedCaller(msg.sender));
        _;
    }

    function initialize(
        string memory name,
        string memory symbol,
        address collateralToken_,
        uint8 collateralDecimals_
    ) external initializer {
        require(
            collateralToken_ != address(0),
            InvalidAddress(collateralToken_)
        );
        _checkDecimals(collateralToken_, collateralDecimals_);

        __CollateralPoolToken_init(name, symbol);
        __CollateralPoolStore_init(
            msg.sender,
            collateralToken_,
            collateralDecimals_
        );
    }

    function collateralToken() external view returns (address) {
        return address(_collateralToken);
    }

    function collateralDecimals() external view returns (uint8) {
        return _collateralDecimals;
    }

    function liquidityBalance() external view returns (uint256) {
        return _liquidityBalance;
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

    function borrowingFeeRateApy() public view returns (uint256 feeRateApy) {
        IBorrowingRate.Global memory globalFr;
        globalFr.baseApy = _borrowingBaseApy();
        IBorrowingRate.Pool memory poolFr = _makeBorrowingContext();
        int256 fr = LibExpBorrowingRate.getBorrowingRate2(globalFr, poolFr);
        return fr.toUint256();
    }

    function liquidityFeeRate() public view returns (uint256 feeRate) {
        feeRate = _liqudityFeeRate();
    }

    function liquidityCapUsd() public view returns (uint256 capUsd) {
        capUsd = _liquidityCapUsd();
    }

    /**
     * @dev an AUM that can be used on chain. it uses on-chain prices and should be similar to _aumUsd
     *      which is used in addLiquidity/removeLiquidity.
     *
     *      this function is never used in MUX3 contracts. other contacts can use this value to estimate
     *      the value of LP token.
     */
    function estimatedAumUsd() public view returns (uint256 aumUsd) {
        // TODO: read chain-link on-chain oracle instead
        uint256 collateralPrice = IFacetReader(_core).priceOf(
            address(_collateralToken)
        );
        aumUsd = _aumUsd(collateralPrice);
    }

    function setLiquidityCapUsd(uint256 capUsd) external {
        // TODO: check sender!
        _configTable.setUint256(MCP_LIQUIDITY_CAP_USD, capUsd);
    }

    function setMarket(bytes32 marketId, bool isLong) external {
        // TODO: check sender!
        require(!_marketIds.contains(marketId), MarketAlreadyExists(marketId));
        require(_marketIds.add(marketId), ArrayAppendFailed());
        _marketStates[marketId].isLong = isLong;
    }

    function setConfig(bytes32 key, bytes32 value) external {
        // TODO: check sender!
        _configTable.setBytes32(key, value);
        emit SetConfig(key, value);
    }

    function configValue(bytes32 key) external view returns (bytes32) {
        return _configTable.getBytes32(key);
    }

    function openPosition(bytes32 marketId, uint256 size) external override {
        // TODO: check sender!
        MarketState storage data = _marketStates[marketId];
        uint256 marketPrice = IFacetReader(_core).priceOf(marketId);
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

    // MUX3 should send fee to this contract
    function receiveFee(address token, uint256 rawAmount) external {
        // TODO: check sender!
        emit ReceiveFee(token, rawAmount);
        if (token == address(_collateralToken)) {
            uint256 wad = _toWad(rawAmount);
            _liquidityBalance += wad;
            emit AddLiquidityFromFee(
                address(_collateralToken),
                IFacetReader(_core).priceOf(address(_collateralToken)),
                wad
            );
        } else {
            // TODO: save tokens as fee and later sell them for collateralToken
        }
    }

    function closePosition(bytes32 marketId, uint256 size) external override {
        // TODO: check sender!
        MarketState storage data = _marketStates[marketId];
        data.totalSize -= size;
        emit ClosePosition(marketId, size, data.totalSize);
    }

    function addLiquidity(
        address account,
        uint256 rawCollateralAmount // OrderBook should transfer _collateralToken to this contract
    ) external override returns (uint256 shares) {
        // TODO: broker only
        require(rawCollateralAmount != 0, "rawCollateralAmount=0");
        // nav
        uint256 collateralPrice = IFacetReader(_core).priceOf(
            address(_collateralToken)
        );
        uint256 aumUsd = _aumUsd(collateralPrice);
        uint256 lpPrice = _nav(aumUsd);
        // token amount
        uint256 collateralAmount = _toWad(rawCollateralAmount);
        uint256 feeCollateral = (collateralAmount * _liqudityFeeRate()) / 1e18;
        collateralAmount -= feeCollateral;
        _liquidityBalance += collateralAmount;
        // cap
        {
            uint256 liquidityCap = liquidityCapUsd();
            uint256 collateralUsd = (collateralAmount * collateralPrice) / 1e18;
            require(
                aumUsd + collateralUsd <= liquidityCap,
                LiquidityCapExceeded(liquidityCap, collateralUsd, aumUsd)
            );
        }
        // send tokens
        shares = (collateralAmount * collateralPrice) / lpPrice;
        _mint(account, shares);
        _distributeFee(account, feeCollateral);
        emit AddLiquidity(
            account,
            address(_collateralToken),
            collateralPrice,
            feeCollateral,
            lpPrice,
            shares
        );
    }

    function removeLiquidity(
        address account,
        uint256 shares
    ) external override returns (uint256 rawCollateralAmount) {
        // TODO: broker only
        require(shares != 0, "shares=0");
        // nav
        uint256 collateralPrice = IFacetReader(_core).priceOf(
            address(_collateralToken)
        );
        uint256 aumUsd = _aumUsd(collateralPrice);
        uint256 lpPrice = _nav(aumUsd);
        // token amount
        uint256 collateralAmount = (shares * lpPrice) / collateralPrice;
        require(
            collateralAmount <= _liquidityBalance,
            InsufficientLiquidity(collateralAmount, _liquidityBalance)
        );
        _liquidityBalance -= collateralAmount;
        uint256 feeCollateral = (collateralAmount * _liqudityFeeRate()) / 1e18;
        collateralAmount -= feeCollateral;
        // send tokens
        _burn(msg.sender, shares); // note: lp token is still in the OrderBook
        _distributeFee(account, feeCollateral);
        rawCollateralAmount = _toRaw(collateralAmount);
        _collateralToken.safeTransfer(account, rawCollateralAmount);
        emit RemoveLiquidity(
            account,
            address(_collateralToken),
            collateralPrice,
            feeCollateral,
            lpPrice,
            shares
        );
    }

    function _distributeFee(
        address lp,
        uint256 feeCollateral // decimals = 18
    ) internal {
        emit CollectFee(address(_collateralToken), feeCollateral);
        address feeDistributor = _feeDistributor();
        if (feeDistributor == address(0)) {
            return;
        }
        _collateralToken.safeTransfer(feeDistributor, _toRaw(feeCollateral));
        IFeeDistributor(feeDistributor).updateLiquidityFees(
            lp,
            address(this), // poolAddress
            feeCollateral // decimals = 18
        );
    }

    function _makeBorrowingContext()
        internal
        view
        returns (IBorrowingRate.Pool memory poolFr)
    {
        poolFr.poolId = address(this);
        poolFr.k = _borrowingK();
        poolFr.b = _borrowingB();
        poolFr.highPriority = _configTable.getBoolean(MCP_IS_HIGH_PRIORITY);
        uint256 collateralPrice = IFacetReader(_core).priceOf(
            address(_collateralToken)
        );
        poolFr.poolSizeUsd = _aumUsdWithoutPnl(collateralPrice).toInt256();
        poolFr.reservedUsd = _reservedUsd().toInt256();
    }

    function _checkDecimals(address token, uint256 decimals) internal view {
        try IERC20MetadataUpgradeable(token).decimals() returns (
            uint8 _decimals
        ) {
            require(
                decimals == _decimals,
                UnmatchedDecimals(decimals, _decimals)
            );
        } catch {}
    }
}
