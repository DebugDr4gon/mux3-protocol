// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import "../../third-party/Diamond.sol";

/**
 * @notice Mux3OwnerFacet is the original OwnerFacet with two-phase verification
 */
contract Mux3OwnerFacet is IERC173 {
    bytes32 constant MUX3_OWNER_FACET_STORAGE_POSITION = keccak256("diamond.mux3.owner.storage");

    struct Storage {
        address pendingOwner;
    }

    function pendingOwner() public view virtual returns (address) {
        Storage storage ds = mux3OwnerStorage();
        return ds.pendingOwner;
    }

    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        Storage storage ds = mux3OwnerStorage();
        ds.pendingOwner = _newOwner;
    }

    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }

    function acceptOwnership() external {
        address pending = pendingOwner();
        if (pending != msg.sender) {
            revert NotContractOwner(msg.sender, pending);
        }
        Storage storage ds = mux3OwnerStorage();
        ds.pendingOwner = address(0);
        LibDiamond.setContractOwner(msg.sender);
    }

    function mux3OwnerStorage() internal pure returns (Storage storage ds) {
        bytes32 position = MUX3_OWNER_FACET_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
