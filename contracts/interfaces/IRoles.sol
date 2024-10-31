// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

bytes32 constant PRICE_SETTER_ROLE = keccak256("PRICE_SETTER_ROLE");
bytes32 constant ORDER_BOOK_ROLE = keccak256("ORDER_BOOK_ROLE");
bytes32 constant BROKER_ROLE = keccak256("BROKER_ROLE");
bytes32 constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");
bytes32 constant DELEGATOR_ROLE = keccak256("DELEGATOR_ROLE");
bytes32 constant FEE_DISTRIBUTOR_USER_ROLE = keccak256(
    "FEE_DISTRIBUTOR_USER_ROLE"
);
