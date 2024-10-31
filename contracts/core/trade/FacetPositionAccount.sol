// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../../interfaces/ITrade.sol";
import "../../libraries/LibTypeCast.sol";

import "../Mux3FacetBase.sol";
import "./PositionAccount.sol";
import "./Market.sol";

contract FacetPositionAccount is
    Mux3FacetBase,
    PositionAccount,
    Market,
    IPositionAccount
{
    using LibTypeCast for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using LibConfigMap for mapping(bytes32 => bytes32);

    /**
     * @dev anyone can updates the borrowing fee for a position and market,
     *      allowing LPs to collect fees even if the position remains open.
     */
    function updateBorrowingFee(bytes32 positionId, bytes32 marketId) external {
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // update borrowing fee
        uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(
            marketId
        );
        uint256 borrowingFeeUsd = _updateAndDispatchBorrowingFeeForAccount(
            positionAccount.owner,
            positionId,
            marketId,
            cumulatedBorrowingPerUsd,
            true
        );
        emit UpdatePositionBorrowingFee(
            positionAccount.owner,
            positionId,
            marketId,
            borrowingFeeUsd
        );
    }

    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 leverage
    ) external onlyRole(ORDER_BOOK_ROLE) {
        // make account if nessary
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // set leverage
        _setInitialLeverage(positionId, marketId, leverage);
        emit SetInitialLeverage(
            positionAccount.owner,
            positionId,
            marketId,
            leverage
        );
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
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // deposit
        _depositToAccount(positionId, collateralToken, rawAmount);
        emit Deposit(
            positionAccount.owner,
            positionId,
            collateralToken,
            rawAmount
        );
    }

    function withdraw(
        bytes32 positionId,
        address collateralToken,
        uint256 rawAmount // token.decimals
    ) external onlyRole(ORDER_BOOK_ROLE) {
        require(
            _isPositionAccountExist(positionId),
            PositionAccountNotExists(positionId)
        );
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // update borrowing fee for all markets
        uint256 allBorrowingFeeUsd;
        uint256 marketLength = positionAccount.activeMarkets.length();
        for (uint256 i = 0; i < marketLength; i++) {
            bytes32 marketId = positionAccount.activeMarkets.at(i);
            uint256[] memory cumulatedBorrowingPerUsd = _updateMarketBorrowing(
                marketId
            );
            uint256 borrowingFeeUsd = _updateAndDispatchBorrowingFeeForAccount(
                positionAccount.owner,
                positionId,
                marketId,
                cumulatedBorrowingPerUsd,
                true // shouldCollateralSufficient
            );
            allBorrowingFeeUsd += borrowingFeeUsd;
        }
        // withdraw
        uint256 collateralAmount = _collateralToWad(collateralToken, rawAmount);
        _withdrawFromAccount(positionId, collateralToken, collateralAmount);
        // exceeds leverage set by setInitialLeverage
        require(
            _isLeverageSafe(positionId),
            UnsafePositionAccount(positionId, SAFE_LEVERAGE)
        );
        // exceeds leverage set by MM_INITIAL_MARGIN_RATE
        require(
            _isInitialMarginSafe(positionId),
            UnsafePositionAccount(positionId, SAFE_INITITAL_MARGIN)
        );
        emit Withdraw(
            positionAccount.owner,
            positionId,
            collateralToken,
            rawAmount,
            allBorrowingFeeUsd
        );
    }

    function withdrawAll(
        bytes32 positionId
    ) external onlyRole(ORDER_BOOK_ROLE) {
        require(
            _isPositionAccountExist(positionId),
            PositionAccountNotExists(positionId)
        );
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // all positions should be closed
        require(
            positionAccount.activeMarkets.length() == 0,
            PositionNotClosed(positionId)
        );
        address[] memory collaterals = positionAccount
            .activeCollaterals
            .values();
        for (uint256 i = 0; i < collaterals.length; i++) {
            address collateralToken = collaterals[i];
            uint256 collateralAmount = positionAccount.collaterals[
                collaterals[i]
            ];
            _withdrawFromAccount(positionId, collateralToken, collateralAmount);
            emit Withdraw(
                positionAccount.owner,
                positionId,
                collateralToken,
                _collateralToRaw(collateralToken, collateralAmount),
                0 // borrowingFee must be 0 because size is 0
            );
        }
    }

    function withdrawUsd(
        bytes32 positionId
    ) external onlyRole(ORDER_BOOK_ROLE) {
        // TODO: implement
    }

    // check FacetTrade.sol: _updateAndDispatchBorrowingFeeForTrade
    // for which is identical
    function _updateAndDispatchBorrowingFeeForAccount(
        address trader,
        bytes32 positionId,
        bytes32 marketId,
        uint256[] memory cumulatedBorrowingPerUsd,
        bool shouldCollateralSufficient
    ) private returns (uint256 borrowingFeeUsd) {
        uint256[] memory borrowingFeeUsds;
        address[] memory borrowingFeeAddresses;
        uint256[] memory borrowingFeeAmounts;
        // note: if shouldCollateralSufficient = false, borrowingFeeUsd could <= sum(borrowingFeeUsds).
        //       we only use borrowingFeeUsds as allocations
        (
            borrowingFeeUsd,
            borrowingFeeUsds,
            borrowingFeeAddresses,
            borrowingFeeAmounts
        ) = _updateAccountBorrowingFee(
            positionId,
            marketId,
            cumulatedBorrowingPerUsd,
            shouldCollateralSufficient
        );
        _dispatchFee(
            trader,
            positionId,
            marketId,
            borrowingFeeAddresses,
            borrowingFeeAmounts,
            borrowingFeeUsds // allocations
        );
    }
}
