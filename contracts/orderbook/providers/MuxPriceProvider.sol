// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../../interfaces/IErrors.sol";
import "../../interfaces/IRoles.sol";

contract MuxPriceProvider is AccessControlUpgradeable {
    struct OracleData {
        bytes32 oracleId;
        uint256 sequence;
        uint256 price;
        uint256 timestamp;
        bytes signature;
    }

    uint256 public sequence;
    uint256 public priceExpiration;

    event SetPriceExpiration(uint256 expiration);

    function initialize() external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setPriceExpirationSeconds(uint256 _priceExpiration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_priceExpiration <= 86400 && _priceExpiration > 30, IErrors.InvalidPriceExpiration(_priceExpiration));
        priceExpiration = _priceExpiration;
        emit SetPriceExpiration(_priceExpiration);
    }

    function getOraclePrice(bytes32 oracleId, bytes memory rawData) external returns (uint256, uint256) {
        OracleData memory oracleData = abi.decode(rawData, (OracleData));
        require(oracleData.oracleId == oracleId, IErrors.IdMismatch(oracleData.oracleId, oracleId));
        require(
            oracleData.timestamp + priceExpiration >= block.timestamp,
            IErrors.PriceExpired(oracleData.timestamp + priceExpiration, block.timestamp)
        );
        require(oracleData.price > 0, IErrors.InvalidPrice(oracleData.price));
        require(oracleData.signature.length > 0, IErrors.MissingSignature());
        require(oracleData.sequence > sequence, IErrors.InvalidSequence(oracleData.sequence, sequence));
        bytes32 message = ECDSAUpgradeable.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    oracleId,
                    block.chainid,
                    address(this),
                    oracleData.sequence,
                    oracleData.price,
                    oracleData.timestamp
                )
            )
        );
        address signer = ECDSAUpgradeable.recover(message, oracleData.signature);
        require(hasRole(ORACLE_SIGNER, signer), IErrors.InvalidSinger(signer));
        sequence = oracleData.sequence;
        return (oracleData.price, oracleData.timestamp);
    }
}
