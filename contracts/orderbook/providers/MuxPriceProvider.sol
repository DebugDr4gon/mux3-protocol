// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MuxPriceProvider is OwnableUpgradeable {
    struct OracleData {
        bytes32 priceId;
        uint256 sequence;
        uint256 price;
        uint256 timestamp;
        bytes signature;
    }

    uint256 public sequence;
    address public oracleSigner;
    uint256 public priceExpiration;

    event SetOracleSigner(address oracleSigner);
    event SetPriceExpiration(uint256 expiration);

    error MissingSignature();
    error InvalidSequence(uint256 sequence, uint256 expectedSequence);
    error InvalidPriceExpiration(uint256 expiration);
    error InvalidPrice(uint256 price);
    error PriceExpired(uint256 timestamp, uint256 blockTimestamp);
    error InvalidSignature(address signer, address expectSigner);
    error IdMismatch(bytes32 id, bytes32 expectedId);

    function initialize(address _oracleSigner) external initializer {
        __Ownable_init();
        _setOracleSigner(_oracleSigner);
    }

    function setPriceExpirationSeconds(
        uint256 _priceExpiration
    ) external onlyOwner {
        require(
            _priceExpiration <= 86400 && _priceExpiration > 30,
            InvalidPriceExpiration(_priceExpiration)
        );
        priceExpiration = _priceExpiration;
        emit SetPriceExpiration(_priceExpiration);
    }

    function setOracleSigner(address _oracleSigner) external onlyOwner {
        _setOracleSigner(_oracleSigner);
    }

    function _setOracleSigner(address _oracleSigner) internal {
        oracleSigner = _oracleSigner;
        emit SetOracleSigner(_oracleSigner);
    }

    function getOraclePrice(
        bytes32 priceId,
        bytes memory rawData
    ) external returns (uint256, uint256) {
        OracleData memory oracleData = abi.decode(rawData, (OracleData));
        require(
            oracleData.priceId == priceId,
            IdMismatch(oracleData.priceId, priceId)
        );
        require(
            oracleData.timestamp + priceExpiration >= block.timestamp,
            PriceExpired(
                oracleData.timestamp + priceExpiration,
                block.timestamp
            )
        );
        require(oracleData.price > 0, InvalidPrice(oracleData.price));
        require(oracleData.signature.length > 0, MissingSignature());
        require(
            oracleData.sequence > sequence,
            InvalidSequence(oracleData.sequence, sequence)
        );
        bytes32 message = ECDSAUpgradeable.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    address(this),
                    oracleData.sequence,
                    oracleData.price,
                    oracleData.timestamp
                )
            )
        );
        address signer = ECDSAUpgradeable.recover(
            message,
            oracleData.signature
        );
        require(signer == oracleSigner, InvalidSignature(signer, oracleSigner));
        sequence++;
        return (oracleData.price, oracleData.timestamp);
    }
}
