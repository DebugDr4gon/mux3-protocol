// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../../libraries/LibCodec.sol";
import "../../interfaces/IPositionAccount.sol";

import "../Mux3FacetBase.sol";

import "hardhat/console.sol";

contract PositionAccount is Mux3FacetBase {
    using LibCodec for bytes32;
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function _setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 initialLeverage
    ) internal {
        require(
            initialLeverage >= 1e18,
            InitialLeverageOutOfRange(initialLeverage, 1e18)
        );
        uint256 maxLeverage = _marketMaxInitialLeverage(marketId);
        require(
            initialLeverage <= maxLeverage,
            InitialLeverageOutOfRange(initialLeverage, maxLeverage)
        );
        _positionAccounts[positionId]
            .positions[marketId]
            .initialLeverage = initialLeverage;
    }

    // OrderBook should transfer collateralToken to this contract
    function _depositToAccount(
        bytes32 positionId,
        address collateralToken,
        uint256 rawCollateralAmount // token.decimals
    ) internal {
        require(positionId != bytes32(0), InvalidId(positionId));
        require(
            _isCollateralExists(collateralToken),
            CollateralNotExists(collateralToken)
        );
        require(rawCollateralAmount != 0, InvalidAmount(rawCollateralAmount));
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        uint256 collateralAmount = _collateralToWad(
            collateralToken,
            rawCollateralAmount
        );
        positionAccount.collaterals[collateralToken] += collateralAmount;
        positionAccount.activeCollaterals.add(collateralToken);
    }

    function _withdrawFromAccount(
        bytes32 positionId,
        address collateralToken,
        uint256 rawCollateralAmount // token.decimals
    ) internal {
        require(positionId != bytes32(0), InvalidId(positionId));
        require(
            _isCollateralExists(collateralToken),
            CollateralNotExists(collateralToken)
        );
        require(rawCollateralAmount != 0, InvalidAmount(rawCollateralAmount));
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        uint256 collateralAmount = _collateralToWad(
            collateralToken,
            rawCollateralAmount
        );
        require(
            positionAccount.collaterals[collateralToken] >= collateralAmount,
            InsufficientBalance(
                positionAccount.collaterals[collateralToken],
                collateralAmount
            )
        );
        positionAccount.collaterals[collateralToken] -= collateralAmount;
        IERC20Upgradeable(collateralToken).safeTransfer(
            positionAccount.owner,
            rawCollateralAmount
        );
        require(
            _isInitialMarginSafe(positionId),
            UnsafePositionAccount(positionId, UNSAFE_INITITAL)
        );
        if (positionAccount.collaterals[collateralToken] == 0) {
            positionAccount.activeCollaterals.remove(collateralToken);
        }
    }

    function _openAccountPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) internal {
        _openPosition(positionId, marketId, size);
        // exceeds leverage setted by setInitialLeverage
        require(
            _isLeverageSafe(positionId),
            UnsafePositionAccount(positionId, UNSAFE_LEVERAGE)
        );
        // exceeds leverage setted by MM_INITIAL_MARGIN_RATE
        require(
            _isInitialMarginSafe(positionId),
            UnsafePositionAccount(positionId, UNSAFE_INITITAL)
        );
    }

    function _closeAccountPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) internal {
        _closePosition(positionId, marketId, size);
        require(
            _isInitialMarginSafe(positionId),
            UnsafePositionAccount(positionId, UNSAFE_MAINTENANCE)
        );
    }

    // note: position.collateral[] is updated in this function. but ERC20 token is not transferred yet.
    function _collectFeeFromCollateral(
        bytes32 positionId,
        uint256 totalFeeUsd
    )
        internal
        returns (address[] memory feeAddresses, uint256[] memory feeAmounts)
    {
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        feeAddresses = positionAccount.activeCollaterals.values();
        feeAmounts = new uint256[](feeAddresses.length);
        uint256 remainFeeUsd = totalFeeUsd;
        for (uint256 i = 0; i < feeAddresses.length; i++) {
            address collateral = feeAddresses[i];
            if (positionAccount.collaterals[collateral] == 0) {
                continue;
            }
            uint256 tokenPrice = _priceOf(collateral);
            require(tokenPrice > 0, "InvalidTokenPrice");
            uint256 balanceUsd = (_positionAccounts[positionId].collaterals[
                collateral
            ] * tokenPrice) / 1e18;
            uint256 feeUsd = MathUpgradeable.min(balanceUsd, remainFeeUsd);
            uint256 feeCollateral = (feeUsd * 1e18) / tokenPrice;
            positionAccount.collaterals[collateral] -= ((feeUsd * 1e18) /
                tokenPrice);
            remainFeeUsd -= feeUsd;
            feeAmounts[i] = feeCollateral;
            if (remainFeeUsd == 0) {
                break;
            }
        }
        require(remainFeeUsd == 0, "insufficient collaterals");
    }

    function _updateAccountBorrowingFee(
        bytes32 marketId,
        bytes32 positionId
    )
        internal
        returns (address[] memory feeAddresses, uint256[] memory feeAmounts)
    {
        uint256 nextCumulatedBorrowingPerUsd = _marketCumulativeBorrowingPerUsd(
            marketId
        );
        uint256 borrowingFeeUsd = _borrowingFeeUsd(
            positionId,
            marketId,
            nextCumulatedBorrowingPerUsd
        );
        (feeAddresses, feeAmounts) = _collectFeeFromCollateral(
            positionId,
            borrowingFeeUsd
        );
        _positionAccounts[positionId]
            .positions[marketId]
            .entryBorrowing = nextCumulatedBorrowingPerUsd;
    }

    function _updatePositionFee(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    )
        internal
        returns (address[] memory feeAddresses, uint256[] memory feeAmounts)
    {
        uint256 feeRate = _marketPositionFeeRate(marketId);
        uint256 marketPrice = _priceOf(marketId);
        uint256 positionFeeUsd = (((size * marketPrice) / 1e18) * feeRate) /
            1e18;
        return _collectFeeFromCollateral(positionId, positionFeeUsd);
    }

    function _openPosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) internal {
        PositionData storage data = _positionAccounts[positionId].positions[
            marketId
        ];
        uint256 price = _priceOf(marketId);
        uint256 nextSize = data.size + size;
        if (data.size == 0) {
            data.entryPrice = price;
        } else {
            data.entryPrice =
                (data.entryPrice * data.size + price * size) /
                nextSize;
        }
        data.size = nextSize;
        data.lastIncreasedTime = block.timestamp;
        _positionAccounts[positionId].activeMarkets.add(marketId);
    }

    function _closePosition(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) internal {
        PositionData storage data = _positionAccounts[positionId].positions[
            marketId
        ];
        data.size -= size;
        if (data.size == 0) {
            data.entryPrice = 0;
            data.entryBorrowing = 0;
            data.lastIncreasedTime = 0;
            _positionAccounts[positionId].activeMarkets.remove(marketId);
        }
    }

    function _isPositionAccountExist(
        bytes32 positionId
    ) internal view returns (bool) {
        return _positionAccounts[positionId].owner != address(0);
    }

    function _createPositionAccount(bytes32 positionId) internal {
        (address owner, ) = positionId.decodePositionId();
        _positionAccounts[positionId].owner = owner;
        _positionAccountLists[owner].add(positionId);
    }

    function _isAccountExist(bytes32 positionId) internal view returns (bool) {
        return _positionAccounts[positionId].owner != address(0);
    }

    function _collateralValue(
        bytes32 positionId
    ) internal view returns (uint256 value) {
        PositionAccountInfo storage account = _positionAccounts[positionId];
        address[] memory collaterals = account.activeCollaterals.values();
        for (uint256 i = 0; i < collaterals.length; i++) {
            uint256 amount = _positionAccounts[positionId].collaterals[
                collaterals[i]
            ];
            if (amount == 0) {
                continue;
            }
            uint256 price = _priceOf(collaterals[i]);
            value += (amount * price) / 1e18;
        }
    }

    function _positionValue(
        bytes32 positionId
    ) internal view returns (uint256 value) {
        PositionAccountInfo storage account = _positionAccounts[positionId];
        bytes32[] memory markets = account.activeMarkets.values();
        for (uint256 i = 0; i < markets.length; i++) {
            PositionData storage data = _positionAccounts[positionId].positions[
                markets[i]
            ];
            if (data.size == 0) {
                continue;
            }
            uint256 price = _priceOf(markets[i]);
            value += (data.size * price) / 1e18;
        }
    }

    function _positionMargin(
        bytes32 positionId
    ) internal view returns (uint256 value) {
        PositionAccountInfo storage account = _positionAccounts[positionId];
        bytes32[] memory markets = account.activeMarkets.values();
        for (uint256 i = 0; i < markets.length; i++) {
            bytes32 marketId = markets[i];
            PositionData storage data = _positionAccounts[positionId].positions[
                marketId
            ];
            if (data.size == 0) {
                continue;
            }
            uint256 price = _priceOf(marketId);
            value += (data.size * price) / _maxLeverage(marketId, positionId);
        }
    }

    function _isInitialMarginSafe(
        bytes32 positionId
    ) internal view returns (bool) {
        return
            _collateralValue(positionId) >=
            _positionValue(positionId) * _marketInitialMarginRate(bytes32(0));
    }

    function _isMaintenanceMarginSafe(
        bytes32 positionId
    ) internal view returns (bool) {
        return
            _collateralValue(positionId) >=
            _positionValue(positionId) *
                _marketMaintenanceMarginRate(bytes32(0));
    }

    function _isLeverageSafe(bytes32 positionId) internal view returns (bool) {
        uint256 collateralValue = _collateralValue(positionId);
        uint256 positionMargin = _positionMargin(positionId);
        return collateralValue > positionMargin;
    }

    function _borrowingFeeUsd(
        bytes32 positionId,
        bytes32 marketId,
        uint256 nextCumulatedBorrowingPerUsd
    ) internal view returns (uint256) {
        PositionData storage data = _positionAccounts[positionId].positions[
            marketId
        ];
        if (data.size == 0) {
            return 0;
        }
        uint256 increasingBorrowing = nextCumulatedBorrowingPerUsd -
            data.entryBorrowing;

        console.log("increasingBorrowing", nextCumulatedBorrowingPerUsd);
        console.log("increasingBorrowing", nextCumulatedBorrowingPerUsd);

        return
            (((data.size * data.entryPrice) / 1e18) * increasingBorrowing) /
            1e18;
    }

    function _maxLeverage(
        bytes32 marketId,
        bytes32 positionId
    ) internal view returns (uint256) {
        uint256 maxLeverage = _positionAccounts[positionId]
            .positions[marketId]
            .initialLeverage;
        if (maxLeverage == 0) {
            maxLeverage = _marketMaxInitialLeverage(marketId);
        }
        return maxLeverage;
    }
}
