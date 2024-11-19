// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

contract TestReferralManager {
    struct TierSetting {
        uint8 tier;
        uint64 stakeThreshold;
        uint64 discountRate;
        uint64 rebateRate;
    }

    mapping(bytes32 => address) public rebateRecipients;
    mapping(address => bytes32) public referralCodeOf;
    mapping(address => uint256) public lastUpdatedTime;
    TierSetting[] public tierSettings;

    function getReferralCodeOf(address trader) external view returns (bytes32, uint256) {
        return (referralCodeOf[trader], lastUpdatedTime[trader]);
    }

    function setReferrerCodeFor(address trader, bytes32 referralCode, address recipient) external {
        referralCodeOf[trader] = referralCode;
        rebateRecipients[referralCode] = recipient;
    }

    function setTierSetting(uint8 tier, uint64 stakeThreshold, uint64 discountRate, uint64 rebateRate) external {
        while (tierSettings.length <= tier) {
            tierSettings.push();
        }
        tierSettings[tier] = TierSetting(tier, stakeThreshold, discountRate, rebateRate);
    }
}
