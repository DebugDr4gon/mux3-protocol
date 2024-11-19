// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// first introduced in mux-degen
interface IReferralTiers {
    function code2Tier(bytes32 code) external view returns (uint256);
}
