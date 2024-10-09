// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../../interfaces/ITrade.sol";
import "../../libraries/LibTypeCast.sol";

import "../Mux3FacetBase.sol";
import "./PositionAccount.sol";
import "./Market.sol";
import "./Pricing.sol";

contract FacetTrade is Mux3FacetBase, PositionAccount, Market, Pricing, ITrade {
    using LibTypeCast for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /**
     * @dev updates the borrowing fee for a position, allowing LPs to collect fees
     *      even if the position remains open.
     */
    function updateBorrowingFee(bytes32 marketId, bytes32 positionId) external {
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        uint256 marketPrice = _priceOf(marketId);
        // update borrowing fee
        _updateMarketBorrowingFee(marketId, marketPrice);
        (
            address[] memory borrowingFeeAddresses,
            uint256[] memory borrowingFeeAmounts
        ) = _updateAccountBorrowingFee(marketId, positionId);
        _dispatchBorrowingFee(
            positionAccount.owner,
            marketId,
            positionId,
            borrowingFeeAddresses,
            borrowingFeeAmounts
        );
        emit UpdateBorrowingFee(
            positionAccount.owner,
            positionId,
            marketId,
            borrowingFeeAddresses,
            borrowingFeeAmounts
        );
    }

    /**
     * @dev this function is typically called automatically when opening or
     *      closing positions, so manual invocation is not required.
     */
    function updateMarketBorrowingFee(bytes32 marketId) internal {
        uint256 tradingPrice = _priceOf(marketId);
        _updateMarketBorrowingFee(marketId, tradingPrice);
    }

    function setInitialLeverage(
        bytes32 positionId,
        bytes32 marketId,
        uint256 leverage
    ) external {
        // auth
        // _checkAuthorization(positionId); // TODO: broker only?
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
    ) external {
        // auth
        // _checkAuthorization(positionId); // TODO: broker only?
        // make account if nessary
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // TODO: update borrowing fee
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
    ) external {
        // TODO: broker only
        // auth
        // _checkAuthorization(positionId); // TODO: broker only?
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        // TODO: update borrowing fee
        // withdraw
        _withdrawFromAccount(positionId, collateralToken, rawAmount);
        emit Withdraw(
            positionAccount.owner,
            positionId,
            collateralToken,
            rawAmount
        );
    }

    function openPosition(
        bytes32 marketId,
        bytes32 positionId,
        uint256 size
    ) external onlyRole(ORDER_BOOK_ROLE) returns (uint256 tradingPrice) {
        require(
            size % _marketLotSize(marketId) == 0,
            InvalidPositionSize(size)
        );
        // auth
        // _checkAuthorization(positionId); // TODO: broker only?
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        tradingPrice = _priceOf(marketId);
        // update borrowing fee
        _updateMarketBorrowingFee(marketId, tradingPrice);
        (
            address[] memory borrowingFeeAddresses,
            uint256[] memory borrowingFeeAmounts
        ) = _updateAccountBorrowingFee(marketId, positionId);
        _dispatchBorrowingFee(
            positionAccount.owner,
            marketId,
            positionId,
            borrowingFeeAddresses,
            borrowingFeeAmounts
        );
        // allocations
        uint256[] memory allocations = _allocateLiquidity(marketId, size);
        // position fee
        (
            address[] memory positionFeeAddresses,
            uint256[] memory positionFeeAmounts
        ) = _updatePositionFee(positionId, marketId, size);
        // position fee
        _dispatchFee(
            positionAccount.owner,
            marketId,
            positionId,
            positionFeeAddresses,
            positionFeeAmounts,
            allocations
        );
        // open position
        _openAccountPosition(positionId, marketId, size);
        _openMarketPosition(marketId, allocations);
        // done
        PositionData storage data = _positionAccounts[positionId].positions[
            marketId
        ];
        emit OpenPosition(
            positionAccount.owner,
            positionId,
            marketId,
            _markets[marketId].isLong,
            size,
            allocations,
            tradingPrice,
            data.entryPrice,
            data.size,
            positionFeeAddresses,
            positionFeeAmounts, // 1e18
            borrowingFeeAddresses,
            borrowingFeeAmounts // 1e18
        );
    }

    function closePosition(
        bytes32 marketId,
        bytes32 positionId,
        uint256 size
    ) external onlyRole(BROKER_ROLE) returns (uint256 tradingPrice) {
        require(
            size % _marketLotSize(marketId) == 0,
            InvalidPositionSize(size)
        );
        // auth
        if (!_isPositionAccountExist(positionId)) {
            _createPositionAccount(positionId);
        }
        PositionAccountInfo storage positionAccount = _positionAccounts[
            positionId
        ];
        tradingPrice = _priceOf(marketId);
        // update borrowing fee
        _updateMarketBorrowingFee(marketId, tradingPrice);
        (
            address[] memory borrowingFeeAddresses,
            uint256[] memory borrowingFeeAmounts
        ) = _updateAccountBorrowingFee(marketId, positionId);
        // allocations
        uint256[] memory allocations = _deallocateLiquidity(marketId, size);
        _dispatchBorrowingFee(
            positionAccount.owner,
            marketId,
            positionId,
            borrowingFeeAddresses,
            borrowingFeeAmounts
        );
        // position fee
        (
            address[] memory positionFeeAddresses,
            uint256[] memory positionFeeAmounts
        ) = _updatePositionFee(positionId, marketId, size);
        // position fee
        _dispatchFee(
            positionAccount.owner,
            marketId,
            positionId,
            positionFeeAddresses,
            positionFeeAmounts,
            allocations
        );
        // close position
        _closeAccountPosition(positionId, marketId, size);
        _closeMarketPosition(marketId, allocations);
        // done
        PositionData storage data = _positionAccounts[positionId].positions[
            marketId
        ];
        emit ClosePosition(
            positionAccount.owner,
            positionId,
            marketId,
            _markets[marketId].isLong,
            size,
            allocations,
            tradingPrice,
            data.entryPrice,
            data.size,
            positionFeeAddresses,
            positionFeeAmounts,
            borrowingFeeAddresses,
            borrowingFeeAmounts
        );
    }

    function setPrice(
        bytes32 priceId,
        address provider,
        bytes memory oracleCalldata
    ) external onlyRole(BROKER_ROLE) {
        (uint256 price, uint256 timestamp) = _setPrice(
            priceId,
            provider,
            oracleCalldata
        );
        emit SetPrice(priceId, provider, oracleCalldata, price, timestamp);
    }
}
