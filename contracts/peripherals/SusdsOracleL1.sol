// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// https://etherscan.io/address/0xa3931d71877c0e7a3148cb7eb4463524fec27fbd
interface ISusds {
    function chi() external view returns (uint192); // The Rate Accumulator  [ray]
    function rho() external view returns (uint64); // Time of last drip      [unix epoch time]
    function ssr() external view returns (uint256); // The USDS Savings Rate [ray]
}

// https://github.com/OffchainLabs/nitro-contracts/blob/main/src/bridge/Inbox.sol
interface IArbitrumInbox {
    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata data
    ) external payable returns (uint256);
}

/**
 * @notice An alternative oracle of sUSDS (issued by Sky). If Chainlink supports sUSDS, we can deprecate this contract.
 *
 *         this contract let anyone to read (chi, ssr, rho) of sUSDS (issued by Sky), and pass the data into SusdsOracleL2 through arbitrum inbox.
 */
contract SusdsOracleL1 is Initializable, OwnableUpgradeable {
    address public inbox;
    address public susdsOracleL2;
    address public susds;

    event OracleUpdated(uint192 chi, uint64 rho, uint256 ssr);

    function initialize(address inbox_, address susdsOracleL2_, address susds_) external initializer {
        __Ownable_init();
        inbox = inbox_;
        susdsOracleL2 = susdsOracleL2_;
        susds = susds_;
    }

    // maxSubmissionCost is at least (1400 + 6 * dataLength) * baseFee defined in Inbox.calculateRetryableSubmissionFee
    // where dataLength = 4 + 32 * 3
    function update(uint256 maxSubmissionCost, uint256 l2GasLimit, uint256 l2GasFee) external payable {
        uint192 chi = ISusds(susds).chi();
        uint64 rho = ISusds(susds).rho();
        uint256 ssr = ISusds(susds).ssr();
        bytes memory data = abi.encodeWithSignature("updateFromL1(uint192,uint64,uint256)", chi, rho, ssr);
        IArbitrumInbox(inbox).createRetryableTicket{ value: msg.value }(
            susdsOracleL2, // target L2 contract
            0, // call value sent to L2
            maxSubmissionCost,
            msg.sender, // refund address for excess submission cost
            msg.sender, // refund address for call value
            l2GasLimit,
            l2GasFee,
            data // encoded data
        );
        emit OracleUpdated(chi, rho, ssr);
    }
}
