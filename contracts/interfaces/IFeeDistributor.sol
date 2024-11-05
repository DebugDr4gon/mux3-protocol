// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IFeeDistributor {
    function updateLiquidityFees(
        address lp,
        address poolAddress,
        uint256 amount // decimals = 18
    ) external;

    // note: allocation only represents a proportional relationship.
    //       the sum of allocations does not necessarily have to be consistent with the total value.
    function updatePositionFees(
        address trader,
        bytes32 positionId,
        bytes32 marketId,
        address[] memory feeAddresses,
        uint256[] memory feeAmounts, // [amount foreach feeAddresses], decimals = 18
        uint256[] memory allocations // [amount foreach backed pools], decimals = 18
    ) external;
}
