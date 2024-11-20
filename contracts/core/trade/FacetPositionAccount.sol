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

    struct WithdrawMemory {
        uint256 allBorrowingFeeUsd;
        uint256 collateralAmount;
        bool isSwapSuccess;
        uint256 rawSwapOut;
    }

    function withdraw(WithdrawArgs memory args) external onlyRole(ORDER_BOOK_ROLE) {
        WithdrawMemory memory mem;
        require(_isPositionAccountExist(args.positionId), PositionAccountNotExists(args.positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        // update borrowing fee for all markets
        mem.allBorrowingFeeUsd = _updateBorrowingForAllMarkets(
            args.positionId,
            args.lastConsumedToken,
            args.isUnwrapWeth
        );
        // withdraw
        mem.collateralAmount = _collateralToWad(args.collateralToken, args.amount);
        (mem.isSwapSuccess, mem.rawSwapOut) = _withdrawFromAccount(
            args.positionId,
            args.collateralToken,
            mem.collateralAmount,
            args.withdrawSwapToken,
            args.withdrawSwapSlippage,
            args.isUnwrapWeth
        );
        emit Withdraw(
            positionAccount.owner,
            args.positionId,
            args.collateralToken,
            mem.collateralAmount,
            mem.isSwapSuccess ? args.withdrawSwapToken : args.collateralToken,
            mem.rawSwapOut
        );
        // exceeds leverage set by setInitialLeverage
        require(_isLeverageSafe(args.positionId), UnsafePositionAccount(args.positionId, SAFE_LEVERAGE));
        // exceeds leverage set by MM_INITIAL_MARGIN_RATE
        require(_isInitialMarginSafe(args.positionId), UnsafePositionAccount(args.positionId, SAFE_INITITAL_MARGIN));
        _dumpForDepositWithdrawEvent(args.positionId, mem.allBorrowingFeeUsd);
    }

    struct WithdrawAllMemory {
        address[] collaterals;
        uint256 collateralAmount;
        bool isSwapSuccess;
        uint256 rawSwapOut;
    }

    function withdrawAll(WithdrawAllArgs memory args) external onlyRole(ORDER_BOOK_ROLE) {
        WithdrawAllMemory memory mem;
        require(_isPositionAccountExist(args.positionId), PositionAccountNotExists(args.positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        // all positions should be closed
        require(positionAccount.activeMarkets.length() == 0, PositionNotClosed(args.positionId));
        mem.collaterals = positionAccount.activeCollaterals.values();
        for (uint256 i = 0; i < mem.collaterals.length; i++) {
            mem.collateralAmount = positionAccount.collaterals[mem.collaterals[i]];
            if (mem.collateralAmount == 0) {
                // usually we do not protect collateralAmount == 0 and the contract should ensure empty collaterals are removed.
                // but since this is usually the last step of trading, we allow withdrawing 0 for better fault tolerance
                continue;
            }
            (mem.isSwapSuccess, mem.rawSwapOut) = _withdrawFromAccount(
                args.positionId,
                mem.collaterals[i],
                mem.collateralAmount,
                args.withdrawSwapToken,
                args.withdrawSwapSlippage,
                args.isUnwrapWeth
            );
            emit Withdraw(
                positionAccount.owner,
                args.positionId,
                mem.collaterals[i],
                mem.collateralAmount,
                mem.isSwapSuccess ? args.withdrawSwapToken : mem.collaterals[i],
                mem.rawSwapOut
            );
        } // emit Withdraw here
        _dumpForDepositWithdrawEvent(
            args.positionId,
            0 // borrowingFeeUsd
        );
    }

    struct WithdrawUsdMemory {
        uint256 allBorrowingFeeUsd;
        address[] collaterals;
        uint256 remainUsd;
        bool isSwapSuccess;
        uint256 rawSwapOut;
        uint256 tokenPrice;
        uint256 payingUsd;
        uint256 payingCollateral;
    }

    function withdrawUsd(WithdrawUsdArgs memory args) external onlyRole(ORDER_BOOK_ROLE) {
        WithdrawUsdMemory memory mem;
        require(_isPositionAccountExist(args.positionId), PositionAccountNotExists(args.positionId));
        PositionAccountInfo storage positionAccount = _positionAccounts[args.positionId];
        // update borrowing fee for all markets
        mem.allBorrowingFeeUsd = _updateBorrowingForAllMarkets(
            args.positionId,
            args.lastConsumedToken,
            args.isUnwrapWeth
        );
        // withdraw
        mem.collaterals = _activeCollateralsWithLastWithdraw(args.positionId, args.lastConsumedToken);
        mem.remainUsd = args.collateralUsd;
        for (uint256 i = 0; i < mem.collaterals.length; i++) {
            mem.tokenPrice = _priceOf(mem.collaterals[i]);
            {
                uint256 balanceUsd = (positionAccount.collaterals[mem.collaterals[i]] * mem.tokenPrice) / 1e18;
                mem.payingUsd = MathUpgradeable.min(balanceUsd, mem.remainUsd);
            }
            mem.payingCollateral = (mem.payingUsd * 1e18) / mem.tokenPrice;
            (mem.isSwapSuccess, mem.rawSwapOut) = _withdrawFromAccount(
                args.positionId,
                mem.collaterals[i],
                mem.payingCollateral,
                args.withdrawSwapToken,
                args.withdrawSwapSlippage,
                args.isUnwrapWeth
            );
            emit Withdraw(
                positionAccount.owner,
                args.positionId,
                mem.collaterals[i],
                mem.payingCollateral,
                mem.isSwapSuccess ? args.withdrawSwapToken : mem.collaterals[i],
                mem.rawSwapOut
            );
            mem.remainUsd -= mem.payingUsd;
            if (mem.remainUsd == 0) {
                break;
            }
        }
        require(mem.remainUsd == 0, InsufficientCollateralUsd(mem.remainUsd));
        // exceeds leverage set by setInitialLeverage
        require(_isLeverageSafe(args.positionId), UnsafePositionAccount(args.positionId, SAFE_LEVERAGE));
        // exceeds leverage set by MM_INITIAL_MARGIN_RATE
        require(_isInitialMarginSafe(args.positionId), UnsafePositionAccount(args.positionId, SAFE_INITITAL_MARGIN));
        _dumpForDepositWithdrawEvent(args.positionId, mem.allBorrowingFeeUsd);
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
            lastConsumedToken,
            isUnwrapWeth
        );
        emit UpdatePositionBorrowingFee(positionAccount.owner, positionId, marketId, borrowingFeeUsd);
    }

    function _updateBorrowingForAllMarkets(
        bytes32 positionId,
        address lastConsumedToken,
        bool isUnwrapWeth
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
                lastConsumedToken,
                isUnwrapWeth
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
