// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../../interfaces/IFacetTrade.sol";
import "../../libraries/LibTypeCast.sol";
import "./TradeBase.sol";

contract FacetPositionAccount is Mux3TradeBase, IFacetPositionAccount {
    using LibTypeCast for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using LibConfigMap for mapping(bytes32 => bytes32);

    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 leverage
    ) external onlyRole(ORDER_BOOK_ROLE) {
        // make account if nessary
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        // set leverage
        _setInitialLeverage(positionId, marketId, leverage);
        emit SetInitialLeverage(positionAccount.owner, positionId, marketId, leverage);
    }

    function deposit(
        bytes32 positionId,
        address collateralToken,
        uint256 rawAmount // token.decimals
    ) external onlyRole(ORDER_BOOK_ROLE) {
        // make account if nessary
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        // deposit
        _depositToAccount(positionId, collateralToken, rawAmount);
        emit Deposit(positionAccount.owner, positionId, collateralToken, rawAmount);
        _dumpForDepositWithdrawEvent(
            positionId,
            0 // borrowingFeeUsd
        );
    }

    function withdraw(
        bytes32 positionId,
        address collateralToken,
        uint256 rawAmount, // token.decimals
        address lastConsumedToken,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external onlyRole(ORDER_BOOK_ROLE) {
        require(_isPositionAccountExist(positionId), PositionAccountNotExists(positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        // update borrowing fee for all markets
        uint256 allBorrowingFeeUsd = _updateBorrowingForAllMarkets(positionId, lastConsumedToken);
        // withdraw
        uint256 collateralAmount = _collateralToWad(collateralToken, rawAmount);
        (bool isSwapSuccess, uint256 rawSwapOut) = _withdrawFromAccount(
            positionId,
            collateralToken,
            collateralAmount,
            withdrawSwapToken,
            withdrawSwapSlippage,
            isUnwrapWeth
        );
        emit Withdraw(
            positionAccount.owner,
            positionId,
            collateralToken,
            collateralAmount,
            isSwapSuccess ? withdrawSwapToken : collateralToken,
            rawSwapOut
        );
        // exceeds leverage set by setInitialLeverage
        require(_isLeverageSafe(positionId), UnsafePositionAccount(positionId, SAFE_LEVERAGE));
        // exceeds leverage set by MM_INITIAL_MARGIN_RATE
        require(_isInitialMarginSafe(positionId), UnsafePositionAccount(positionId, SAFE_INITITAL_MARGIN));
        _dumpForDepositWithdrawEvent(positionId, allBorrowingFeeUsd);
    }

    function withdrawAll(
        bytes32 positionId,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external onlyRole(ORDER_BOOK_ROLE) {
        require(_isPositionAccountExist(positionId), PositionAccountNotExists(positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        // all positions should be closed
        require(positionAccount.activeMarkets.length() == 0, PositionNotClosed(positionId));
        address[] memory collaterals = positionAccount.activeCollaterals.values();
        for (uint256 i = 0; i < collaterals.length; i++) {
            address collateralToken = collaterals[i];
            uint256 collateralAmount = positionAccount.collaterals[collateralToken];
            if (collateralAmount == 0) {
                // usually we do not protect collateralAmount == 0 and the contract should ensure empty collaterals are removed.
                // but since this is usually the last step of trading, we allow withdrawing 0 for better fault tolerance
                continue;
            }
            (bool isSwapSuccess, uint256 rawSwapOut) = _withdrawFromAccount(
                positionId,
                collateralToken,
                collateralAmount,
                withdrawSwapToken,
                withdrawSwapSlippage,
                isUnwrapWeth
            );
            emit Withdraw(
                positionAccount.owner,
                positionId,
                collateralToken,
                collateralAmount,
                isSwapSuccess ? withdrawSwapToken : collateralToken,
                rawSwapOut
            );
        } // emit Withdraw here
        _dumpForDepositWithdrawEvent(
            positionId,
            0 // borrowingFeeUsd
        );
    }

    function withdrawUsd(
        bytes32 positionId,
        uint256 collateralUsd, // 1e18
        address lastConsumedToken,
        bool isUnwrapWeth,
        address withdrawSwapToken,
        uint256 withdrawSwapSlippage
    ) external onlyRole(ORDER_BOOK_ROLE) {
        require(_isPositionAccountExist(positionId), PositionAccountNotExists(positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        // update borrowing fee for all markets
        uint256 allBorrowingFeeUsd = _updateBorrowingForAllMarkets(positionId, lastConsumedToken);
        // withdraw
        address[] memory collaterals = _activeCollateralsWithLastWithdraw(positionId, lastConsumedToken);
        uint256 remainUsd = collateralUsd;
        for (uint256 i = 0; i < collaterals.length; i++) {
            address collateralToken = collaterals[i];
            uint256 tokenPrice = _priceOf(collateralToken);
            uint256 balanceUsd = (positionAccount.collaterals[collateralToken] * tokenPrice) / 1e18;
            uint256 payingUsd = MathUpgradeable.min(balanceUsd, remainUsd);
            uint256 payingCollateral = (payingUsd * 1e18) / tokenPrice;
            (bool isSwapSuccess, uint256 rawSwapOut) = _withdrawFromAccount(
                positionId,
                collateralToken,
                payingCollateral,
                withdrawSwapToken,
                withdrawSwapSlippage,
                isUnwrapWeth
            );
            emit Withdraw(
                positionAccount.owner,
                positionId,
                collateralToken,
                payingCollateral,
                isSwapSuccess ? withdrawSwapToken : collateralToken,
                rawSwapOut
            );
            remainUsd -= payingUsd;
            if (remainUsd == 0) {
                break;
            }
        }
        require(remainUsd == 0, InsufficientCollateralUsd(remainUsd));
        _dumpForDepositWithdrawEvent(positionId, allBorrowingFeeUsd);
        // exceeds leverage set by setInitialLeverage
        require(_isLeverageSafe(positionId), UnsafePositionAccount(positionId, SAFE_LEVERAGE));
        // exceeds leverage set by MM_INITIAL_MARGIN_RATE
        require(_isInitialMarginSafe(positionId), UnsafePositionAccount(positionId, SAFE_INITITAL_MARGIN));
    }

    /**
     * @dev Updates the borrowing fee for a position and market,
     *      allowing LPs to collect fees even if the position remains open.
     */
    function updateBorrowingFee(
        bytes32 positionId,
        bytes32 marketId,
        address lastConsumedToken
    ) external onlyRole(ORDER_BOOK_ROLE) {
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        // update borrowing fee
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(marketId);
        uint256 borrowingFeeUsd = _updateAndDispatchBorrowingFee(
            positionAccount.owner,
            positionId,
            marketId,
            cumulatedBorrowingPerUsd,
            true,
            lastConsumedToken
        );
        emit UpdatePositionBorrowingFee(positionAccount.owner, positionId, marketId, borrowingFeeUsd);
    }

    function _updateBorrowingForAllMarkets(
        bytes32 positionId,
        address lastConsumedToken
    ) private returns (uint256 allBorrowingFeeUsd) {
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        uint256 marketLength = positionAccount.activeMarkets.length();
        for (uint256 i = 0; i < marketLength; i++) {
            bytes32 marketId = positionAccount.activeMarkets.at(i);
            uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(marketId);
            uint256 borrowingFeeUsd = _updateAndDispatchBorrowingFee(
                positionAccount.owner,
                positionId,
                marketId,
                cumulatedBorrowingPerUsd,
                true, // shouldCollateralSufficient
                lastConsumedToken
            );
            allBorrowingFeeUsd += borrowingFeeUsd;
        }
    }

    function _dumpForDepositWithdrawEvent(bytes32 positionId, uint256 borrowingFeeUsd) private {
        PositionAccountInfo storage positionAccount = _positionAccounts[positionId];
        address[] memory collateralTokens = positionAccount.activeCollaterals.values();
        uint256[] memory collateralAmounts = new uint256[](collateralTokens.length);
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            collateralAmounts[i] = positionAccount.collaterals[collateralTokens[i]];
        }
        emit DepositWithdrawFinish(
            positionAccount.owner,
            positionId,
            borrowingFeeUsd,
            collateralTokens,
            collateralAmounts
        );
    }
}
