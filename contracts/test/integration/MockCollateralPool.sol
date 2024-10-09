// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/LibConfigTable.sol";
import "../../interfaces/ICollateralPool.sol";
import "../../interfaces/IBorrowingRate.sol";
import "../../interfaces/IErrors.sol";
import "../../libraries/LibExpBorrowingRate.sol";
import "../../libraries/LibTypeCast.sol";
import "../../pool/CollateralPoolToken.sol";
import "../../pool/CollateralPoolStore.sol";
import "../../pool/CollateralPoolComputed.sol";

import "hardhat/console.sol";

contract MockCollateralPool is
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

    function initialize(
        string memory name,
        string memory symbol,
        address collateralToken_,
        uint8 collateralDecimals_
    ) external initializer {
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

    function marketState(
        bytes32 marketId
    ) external view returns (MarketState memory) {
        return _marketStates[marketId];
    }

    function markets() external view returns (bytes32[] memory) {}

    function borrowingFeeRateApy() public pure returns (uint256 feeRateApy) {
        return 0;
    }

    function liquidityFeeRate() public view returns (uint256 feeRate) {
        feeRate = _liqudityFeeRate();
    }

    function liquidityCapUsd() public view returns (uint256 capUsd) {
        capUsd = _liquidityCapUsd();
    }

    function setLiquidityCapUsd(uint256 capUsd) external {
        _configTable.setUint256(MCP_LIQUIDITY_CAP_USD, capUsd);
    }

    function setMarket(bytes32 marketId, bool isLong) external {
        require(!_marketIds.contains(marketId), MarketAlreadyExists(marketId));
        require(_marketIds.add(marketId), ArrayAppendFailed());
        _marketStates[marketId].isLong = isLong;
    }

    function setConfig(bytes32 key, bytes32 value) external {
        _configTable.setBytes32(key, value);
    }

    function openPosition(bytes32 marketId, uint256 size) external override {}

    function receiveFee(address token, uint256 rawAmount) external {}

    function closePosition(bytes32 marketId, uint256 size) external override {}

    function addLiquidity(
        address account,
        uint256 collateralAmount
    ) external override returns (uint256 shares) {}

    function removeLiquidity(
        address account,
        uint256 shares
    ) external override returns (uint256 collateralAmount) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
