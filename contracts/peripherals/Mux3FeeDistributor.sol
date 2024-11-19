// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IMux3FeeDistributor.sol";
import "../interfaces/IFacetReader.sol";
import "../interfaces/IReferralManager.sol";
import "../interfaces/IReferralTiers.sol";
import "../interfaces/IMarket.sol";
import "../interfaces/IRoles.sol";
import "../interfaces/IMux3Core.sol";

contract Mux3FeeDistributor is Initializable, AccessControlEnumerableUpgradeable, IMux3FeeDistributor {
    address private _mux3Facet;
    address private _referralManager;
    address private _referralTiers;

    modifier onlyFeeDistributorUser() {
        require(hasFeeDistributorUserRole(msg.sender), "Not a valid fee distributor user");
        _;
    }

    function initialize(address mux3Facet_, address referralManager_, address referralTiers_) external initializer {
        __AccessControlEnumerable_init();
        _mux3Facet = mux3Facet_;
        _referralManager = referralManager_;
        _referralTiers = referralTiers_;
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
    ) external override onlyFeeDistributorUser {
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
    ) external override onlyFeeDistributorUser {
        // TODO: not implemented
        // foreach collateral
        //   pool_fee_i = fee * allocation_i / Σallocation_i
        require(feeAddresses.length == feeAmounts.length, "feeAddresses and feeAmounts mismatched");
        BackedPoolState[] memory backedPools = IFacetReader(_mux3Facet).listMarketPools(marketId);
        require(backedPools.length == allocations.length, "backedPools and allocations mismatched");
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

    function hasFeeDistributorUserRole(address addr) public view returns (bool) {
        if (hasRole(FEE_DISTRIBUTOR_USER_ROLE, addr)) {
            // please add mux3 core and future mux series protocol to this role
            return true;
        }
        if (_isCollateralPool(addr)) {
            // mux3 collateral pools are also valid
            return true;
        }
        return false;
    }

    function setReferralManagers(
        address referralManager_,
        address referralTiers_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _referralManager = referralManager_;
        _referralTiers = referralTiers_;
    }

    function claimVeReward(uint8 tokenId) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(MAINTAINER_ROLE, msg.sender), "Admin or Maintainer");
    }

    /**
     * @dev The referral code determines the discount and rebate rates.
     */
    function getCodeOf(
        address trader
    )
        public
        view
        returns (
            bytes32 code,
            address codeRecipient,
            uint256 tier, // 1e0
            uint256 discountRate, // 1e18
            uint256 rebateRate // 1e18
        )
    {
        (code, ) = IReferralManager(_referralManager).getReferralCodeOf(trader);
        if (code != bytes32(0)) {
            codeRecipient = IReferralManager(_referralManager).rebateRecipients(code);
            tier = IReferralTiers(_referralTiers).code2Tier(code);
            (, , uint64 rate1, uint64 rate2) = IReferralManager(_referralManager).tierSettings(tier);
            // convert 1e5 to 1e18
            discountRate = uint256(rate1) * 10 ** 13;
            rebateRate = uint256(rate2) * 10 ** 13;
        } else {
            // empty referral code is not tier 0, but zero discount/rebate
        }
    }

    function _isCollateralPool(address pool) internal view returns (bool) {
        return IFacetReader(_mux3Facet).getCollateralPool(pool);
    }

    function _validateCollateral(address collateral) internal view {
        (bool enabled, ) = IFacetReader(_mux3Facet).getCollateralToken(collateral);
        require(enabled, "Invalid collateralToken");
    }
}
