// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/LibConfigMap.sol";
import "../../interfaces/ICollateralPool.sol";
import "../../interfaces/IBorrowingRate.sol";
import "../../interfaces/IErrors.sol";
import "../../libraries/LibExpBorrowingRate.sol";
import "../../libraries/LibTypeCast.sol";
import "../../pool/CollateralPoolToken.sol";
import "../../pool/CollateralPoolStore.sol";
import "../../pool/CollateralPoolComputed.sol";

contract MockCollateralPool is
    CollateralPoolToken,
    CollateralPoolStore,
    CollateralPoolComputed,
    ICollateralPool,
    IErrors
{
    using LibConfigMap for mapping(bytes32 => bytes32);
    using LibTypeCast for int256;
    using LibTypeCast for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    constructor(address core_, address orderBook_, address weth_) {
        _core = core_;
        _orderBook = orderBook_;
        _weth = weth_;
    }

    function initialize(string memory name, string memory symbol, address collateralToken_) external initializer {
        __CollateralPoolToken_init(name, symbol);
        __CollateralPoolStore_init(collateralToken_);
    }

    function collateralToken() external view returns (address) {
        return _collateralToken;
    }

    function markets() external view returns (bytes32[] memory) {}

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

    function borrowingFeeRateApy(bytes32 marketId) public pure returns (uint256 feeRateApy) {}

    function setMarket(bytes32 marketId, bool isLong) external {
        require(!_marketIds.contains(marketId), MarketAlreadyExist(marketId));
        require(_marketIds.add(marketId), ArrayAppendFailed());
        _marketStates[marketId].isLong = isLong;
    }

    function setConfig(bytes32 key, bytes32 value) external {
        _configTable.setBytes32(key, value);
    }

    function configValue(bytes32 key) external view returns (bytes32) {
        return _configTable.getBytes32(key);
    }

    function openPosition(bytes32 marketId, uint256 size) external override {}

    function receiveFee(address token, uint256 rawAmount) external {}

    function closePosition(bytes32 marketId, uint256 size, uint256 entryPrice) external override {}

    function realizeProfit(uint256 pnlUsd) external returns (address token, uint256 wad) {}

    function realizeLoss(address token, uint256 rawAmount) external {}

    function addLiquidity(AddLiquidityArgs memory args) external override returns (AddLiquidityResult memory result) {}

    function removeLiquidity(
        RemoveLiquidityArgs memory args
    ) external override returns (RemoveLiquidityResult memory result) {}

    function rebalance(
        address rebalancer,
        address token0,
        uint256 rawAmount0,
        uint256 maxRawAmount1,
        bytes memory userData
    ) external returns (uint256 rawAmount1) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function updateMarketBorrowing(bytes32 marketId) external returns (uint256 newCumulatedBorrowingPerUsd) {}

    function makeBorrowingContext(bytes32 marketId) external view returns (IBorrowingRate.AllocatePool memory) {}

    function positionPnl(
        bytes32 marketId,
        uint256 size,
        uint256 entryPrice,
        uint256 marketPrice
    ) external view returns (int256 pnlUsd, int256 cappedPnlUsd) {}

    function liquidityBalances() external view returns (address[] memory tokens, uint256[] memory balances) {}
}
