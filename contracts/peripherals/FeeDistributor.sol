// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IFeeDistributor.sol";
import "../interfaces/IFacetReader.sol";
import "../interfaces/IPositionAccount.sol";
import "../interfaces/IMarket.sol";
import "../interfaces/IRoles.sol";
import "../interfaces/IMux3Core.sol";

contract FeeDistributor is
    Initializable,
    AccessControlEnumerableUpgradeable,
    IFeeDistributor
{
    address private _mux3Facet;

    function initialize(address mux3Facet) external initializer {
        __AccessControlEnumerable_init();
        _mux3Facet = mux3Facet;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MAINTAINER_ROLE, msg.sender);
    }

    /**
     * @dev MUX3 core collects liquidity fees when fillLiquidityOrder.
     *
     *      note: MUX3 core should send fees to this contract before calling this function.
     */
    function updateLiquidityFees(
        address lp,
        address poolAddress,
        uint256 amount // decimals = 18
    ) external override onlyRole(FEE_DISTRIBUTOR_USER_ROLE) {
        // TODO: not implemented
    }

    /**
     * @dev MUX3 core collects position fees when closePosition.
     *
     *      note: MUX3 core should send fees to this contract before calling this function.
     * @param allocations only represents a proportional relationship. the sum of allocations does not
     *                    necessarily have to be consistent with the total value.
     */
    function updatePositionFees(
        address trader,
        bytes32 positionId,
        bytes32 marketId,
        address[] memory feeAddresses,
        uint256[] memory feeAmounts, // [amount foreach feeAddresses], decimals = 18
        uint256[] memory allocations // [amount foreach backed pools], decimals = 18
    ) external override onlyRole(FEE_DISTRIBUTOR_USER_ROLE) {
        // TODO: not implemented
        // foreach collateral
        //   pool_fee_i = fee * allocation_i / Σallocation_i
        require(
            feeAddresses.length == feeAmounts.length,
            "feeAddresses and feeAmounts mismatched"
        );
        BackedPoolState[] memory backedPools = IFacetReader(_mux3Facet)
            .listMarketPools(marketId);
        require(
            backedPools.length == allocations.length,
            "backedPools and allocations mismatched"
        );
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocation += allocations[i];
        }
        if (totalAllocation == 0) {
            return;
        }
        // for (uint256 fi = 0; fi < length; fi++) {
        //     address backedPool = market.pools[i].backedPool;
        //     address feeToken = ICollateralPool(backedPool).collateralToken();
        //     uint256 feeAmount = feeAmounts[fi];
        //     for (uint256 pi = 0; pi < _markets[marketId].pools.length; pi++) {
        //         BackedPoolState storage pool = _markets[marketId].pools[pi];
        //         uint256 amount = (feeAmount * allocations[pi]) /
        //             totalAllocation;
        //         uint256 rawAmount = _collateralToRaw(feeToken, amount);
        //         IERC20Upgradeable(feeToken).safeTransfer(
        //             pool.backedPool,
        //             rawAmount
        //         );
        //         ICollateralPool(pool.backedPool).receiveFee(
        //             feeToken,
        //             rawAmount
        //         );
        //     }
        // }
    }
}
