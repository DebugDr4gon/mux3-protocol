// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../interfaces/IReferralTiers.sol";

contract TestReferralTiers is IReferralTiers {
    mapping(bytes32 => uint256) public code2Tier;

    function setTier(bytes32[] memory codes, uint256[] memory tiers) external {
        require(codes.length == tiers.length, "Length mismatch");
        for (uint256 i = 0; i < codes.length; i++) {
            code2Tier[codes[i]] = tiers[i];
        }
    }

    function getTiers(bytes32[] memory codes) external view returns (uint256[] memory) {
        uint256[] memory tiers = new uint256[](codes.length);
        for (uint256 i = 0; i < codes.length; i++) {
            tiers[i] = code2Tier[codes[i]];
        }
        return tiers;
    }
}
