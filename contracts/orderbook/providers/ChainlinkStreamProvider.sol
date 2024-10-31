// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../interfaces/chainlink/ICommon.sol";
import "../../interfaces/chainlink/IFeeManager.sol";
import "../../interfaces/chainlink/IVerifyProxy.sol";

contract ChainlinkStreamProvider is OwnableUpgradeable {
    struct Report {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified onchain
        int192 price; // DON consensus median price, carried to 8 decimal places
        int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation
        int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation
    }

    address public chainlinkVerifier;
    uint256 public priceExpiration;
    mapping(bytes32 => bytes32) public feedIds;
    mapping(address => bool) public callerWhitelist;

    event SetChainlinkVerifier(address chainlinkVerifier);
    event SetPriceExpiration(uint256 expiration);
    event SetFeedId(bytes32 priceId, bytes32 feedId);
    event SetCallerWhitelist(address caller, bool isWhitelisted);
    error InvalidChainlinkVerifier();
    error InvalidPrice(int192 price);
    error InvalidPriceExpiration(uint256 expiration);
    error PriceExpired(uint256 timestamp, uint256 blockTimestamp);
    error IdMismatch(bytes32 id, bytes32 expectedId);
    error NotWhitelisted(address caller);

    modifier onlyWhitelisted() {
        require(callerWhitelist[msg.sender], NotWhitelisted(msg.sender));
        _;
    }

    function initialize(address _chainlinkVerifier) external initializer {
        __Ownable_init();
        _setChainlinkVerifier(_chainlinkVerifier);
    }

    function setCallerWhitelist(
        address caller,
        bool isWhitelisted
    ) external onlyOwner {
        callerWhitelist[caller] = isWhitelisted;
        emit SetCallerWhitelist(caller, isWhitelisted);
    }

    function setChainlinkVerifier(
        address _chainlinkVerifier
    ) external onlyOwner {
        _setChainlinkVerifier(_chainlinkVerifier);
    }

    function setPriceExpirationSeconds(
        uint256 _priceExpiration
    ) external onlyOwner {
        require(
            _priceExpiration <= 86400 && _priceExpiration > 0,
            InvalidPriceExpiration(_priceExpiration)
        );
        priceExpiration = _priceExpiration;
        emit SetPriceExpiration(_priceExpiration);
    }

    function setFeedId(bytes32 priceId, bytes32 feedId) external onlyOwner {
        feedIds[priceId] = feedId;
        emit SetFeedId(priceId, feedId);
    }

    function getOraclePrice(
        bytes32 priceId,
        bytes memory rawData
    ) external onlyWhitelisted returns (uint256 price, uint256 timestamp) {
        require(chainlinkVerifier != address(0), InvalidChainlinkVerifier());
        bytes memory unverifiedReport = rawData;
        // Report verification fees
        IVerifyProxy verifier = IVerifyProxy(chainlinkVerifier);
        IFeeManager feeManager = IFeeManager(verifier.s_feeManager());
        address rewardManager = feeManager.i_rewardManager();
        address feeTokenAddress = feeManager.i_linkAddress();
        (, /* bytes32[3] reportContextData */ bytes memory reportData) = abi
            .decode(unverifiedReport, (bytes32[3], bytes));
        (Asset memory fee, , ) = feeManager.getFeeAndReward(
            address(this),
            reportData,
            feeTokenAddress
        );
        // Approve rewardManager to spend this contract's balance in fees
        IERC20Upgradeable(feeTokenAddress).approve(rewardManager, fee.amount);
        // Verify the report
        bytes memory verifiedReportData = verifier.verify(
            unverifiedReport,
            abi.encode(feeTokenAddress)
        );
        Report memory verifiedReport = abi.decode(verifiedReportData, (Report));
        require(
            verifiedReport.feedId == feedIds[priceId],
            IdMismatch(verifiedReport.feedId, feedIds[priceId])
        );
        require(verifiedReport.price > 0, InvalidPrice(verifiedReport.price));
        require(
            verifiedReport.expiresAt >= block.timestamp,
            PriceExpired(verifiedReport.expiresAt, block.timestamp)
        );

        price = uint256(uint192(verifiedReport.price));
        timestamp = uint256(verifiedReport.observationsTimestamp);
        require(
            timestamp + priceExpiration >= block.timestamp,
            PriceExpired(timestamp + priceExpiration, block.timestamp)
        );
    }

    function _setChainlinkVerifier(address _chainlinkVerifier) internal {
        require(_chainlinkVerifier != address(0), InvalidChainlinkVerifier());
        chainlinkVerifier = _chainlinkVerifier;
        emit SetChainlinkVerifier(_chainlinkVerifier);
    }
}
