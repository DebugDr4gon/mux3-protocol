// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/beacon/IBeaconUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "../Mux3FacetBase.sol";

contract PoolManager is Mux3FacetBase {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function _setImplementation(address newImplementation) internal {
        require(newImplementation != address(0), InvalidAddress(newImplementation));
        require(newImplementation != _collateralPoolImplementation, DuplicatedAddress(newImplementation));
        _collateralPoolImplementation = newImplementation;
    }

    function _createCollateralPool(
        string memory name,
        string memory symbol,
        address collateralToken
    ) internal returns (address) {
        require(collateralToken != address(0), InvalidAddress(collateralToken));
        address pool = _createPoolProxy(name, symbol, collateralToken);
        require(address(pool) != address(0), InvalidAddress(pool));
        require(
            _collateralPoolList.length() < MAX_COLLATERAL_POOLS,
            CapacityExceeded(MAX_COLLATERAL_POOLS, _collateralPoolList.length(), 1)
        );
        require(_collateralPoolList.add(address(pool)), PoolAlreadyExist(pool));
        return address(pool);
    }

    function _setPoolConfigs(address pool, bytes32 key, bytes32 value) internal {
        require(pool != address(0), InvalidAddress(pool));
        require(_isPoolExist(pool), PoolNotExists(pool));
        ICollateralPool(pool).setConfig(key, value);
    }

    function _getProxyId(
        string memory name,
        string memory symbol,
        address collateralToken
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(name, symbol, collateralToken));
    }

    function _getBytesCode(
        string memory name,
        string memory symbol,
        address collateralToken
    ) internal view returns (bytes memory) {
        bytes memory initCallData = abi.encodeWithSignature(
            "initialize(string,string,address)",
            name,
            symbol,
            collateralToken
        );
        bytes memory byteCode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(address(this), initCallData)
        );
        return byteCode;
    }

    function _createPoolProxy(
        string memory name,
        string memory symbol,
        address collateralToken
    ) internal returns (address) {
        bytes memory byteCode = _getBytesCode(name, symbol, collateralToken);
        bytes32 salt = _getProxyId(name, symbol, collateralToken);
        return _createProxy(byteCode, salt);
    }

    function _createProxy(bytes memory bytecode, bytes32 salt) internal returns (address proxy) {
        assembly {
            proxy := create2(0x0, add(0x20, bytecode), mload(bytecode), salt)
        }
        require(proxy != address(0), CreateProxyFailed());
    }

    function _getPoolAddress(
        string memory name,
        string memory symbol,
        address collateralToken
    ) internal view returns (address) {
        bytes memory byteCode = _getBytesCode(name, symbol, collateralToken);
        bytes32 salt = _getProxyId(name, symbol, collateralToken);
        return _getAddress(byteCode, salt);
    }

    function _getAddress(bytes memory bytecode, bytes32 salt) internal view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}
