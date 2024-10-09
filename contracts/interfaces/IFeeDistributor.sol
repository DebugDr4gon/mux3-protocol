// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

interface IFeeDistributor {
    function updateLiquidityFees(
        address lp,
        address poolAddress,
        uint256 amount // decimals = 18
    ) external;
    function updatePositionFees(
        address trader,
        bytes32 marketId,
        bytes32 positionId,
        address[] memory feeAddresses,
        uint256[] memory feeAmounts, // [amount foreach feeAddresses], decimals = 18
        uint256[] memory allocations // [amount foreach backed pools], decimals = 18
    ) external;
}
