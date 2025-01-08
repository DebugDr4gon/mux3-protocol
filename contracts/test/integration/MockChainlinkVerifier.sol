// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../interfaces/chainlink/IVerifyProxy.sol";
import "../../interfaces/chainlink/IFeeManager.sol";

contract MockFeeManager is IFeeManager {
    address feeToken;

    function setFeeToken(address _feeToken) external {
        feeToken = _feeToken;
    }

    function getFeeAndReward(
        address subscriber,
        bytes memory report,
        address quoteAddress
    ) external returns (Asset memory, Asset memory, uint256) {}

    function i_rewardManager() external view returns (address) {
        return address(this);
    }

    function i_linkAddress() external view returns (address) {
        return feeToken;
    }
}

contract MockChainlinkVerifier is IVerifyProxy {
    struct Report {
        bytes32 feedId;
        uint32 validFromTimestamp;
        uint32 observationsTimestamp;
        uint192 nativeFee;
        uint192 linkFee;
        uint32 expiresAt;
        int192 price;
        int192 bid;
        int192 ask;
    }

    Report mockReport;

    address feeManager;

    function setFeeManager(address _feeManager) external {
        feeManager = _feeManager;
    }

    function setMockReport(bytes32 feedId, uint32 expiresAt, uint32 observationsTimestamp, int192 price) external {
        mockReport = Report({
            feedId: feedId,
            validFromTimestamp: 0,
            observationsTimestamp: observationsTimestamp,
            nativeFee: 0,
            linkFee: 0,
            expiresAt: expiresAt,
            price: price,
            bid: 0,
            ask: 0
        });
    }

    function verify(
        bytes calldata payload,
        bytes calldata parameterPayload
    ) external payable returns (bytes memory verifierResponse) {
        return abi.encode(mockReport);
    }

    function verifyBulk(
        bytes[] calldata payloads,
        bytes calldata parameterPayload
    ) external payable returns (bytes[] memory verifiedReports) {}

    function s_feeManager() external view returns (address) {
        return feeManager;
    }
}
