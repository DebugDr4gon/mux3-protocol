// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../../interfaces/IMux3FeeDistributor.sol";
import "../../interfaces/IFacetReader.sol";
import "../../interfaces/IPositionAccount.sol";
import "../../interfaces/IMarket.sol";
import "../../interfaces/IRoles.sol";

contract MockMux3FeeDistributor is IMux3FeeDistributor {
    address private _mux3Facet;

    constructor(address mux3Facet) {
        _mux3Facet = mux3Facet;
    }

    function updateLiquidityFees(
        address lp,
        address poolAddress,
        address tokenAddress,
        uint256 rawAmount, // token decimals
        bool isUnwrapWeth
    ) external override {}

    // note: allocation only represents a proportional relationship.
    //       the sum of allocations does not necessarily have to be consistent with the total value.
    function updatePositionFees(
        address trader,
        address[] memory tokenAddresses,
        uint256[] memory rawAmounts, // [amount foreach tokenAddresses], token decimals
        address[] memory backedPools,
        uint256[] memory allocations, // [amount foreach backed pools], decimals = 18
        bool isUnwrapWeth
    ) external override {}
}
