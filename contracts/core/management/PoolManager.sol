// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/beacon/IBeaconUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "../Mux3FacetBase.sol";

contract PoolManager is Mux3FacetBase {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function _setImplementation(address newImplementation) internal {
        require(
            newImplementation != address(0),
            InvalidAddress(newImplementation)
        );
        require(
            newImplementation != _collateralPoolImplementation,
            DuplicatedAddress(newImplementation)
        );
        _collateralPoolImplementation = newImplementation;
    }

    function _createCollateralPool(
        string memory name,
        string memory symbol,
        address collateralToken,
        uint8 collateralDecimals
    ) internal returns (address) {
        require(collateralToken != address(0), InvalidAddress(collateralToken));
        require(collateralDecimals <= 18, InvalidDecimals(collateralDecimals));
        address pool = _createPoolProxy(
            name,
            symbol,
            collateralToken,
            collateralDecimals
        );
        require(address(pool) != address(0), InvalidAddress(pool));
        require(_collateralPoolList.add(address(pool)), PoolAlreadyExist(pool));
        return address(pool);
    }

    function _setPoolConfigs(
        address pool,
        bytes32 key,
        bytes32 value
    ) internal {
        require(pool != address(0), InvalidAddress(pool));
        require(_isPoolExist(pool), PoolNotExists(pool));
        ICollateralPool(pool).setConfig(key, value);
    }

    function _getProxyId(
        string memory name,
        string memory symbol,
        address collateralToken,
        uint8 collateralDecimals
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    name,
                    symbol,
                    collateralToken,
                    collateralDecimals
                )
            );
    }

    function _getBytesCode(
        string memory name,
        string memory symbol,
        address collateralToken,
        uint8 collateralDecimals
    ) internal view returns (bytes memory) {
        bytes memory initCallData = abi.encodeWithSignature(
            "initialize(string,string,address,uint8)",
            name,
            symbol,
            collateralToken,
            collateralDecimals
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
        address collateralToken,
        uint8 collateralDecimals
    ) internal returns (address) {
        bytes memory byteCode = _getBytesCode(
            name,
            symbol,
            collateralToken,
            collateralDecimals
        );
        bytes32 salt = _getProxyId(
            name,
            symbol,
            collateralToken,
            collateralDecimals
        );
        return _createProxy(byteCode, salt);
    }

    function _createProxy(
        bytes memory bytecode,
        bytes32 salt
    ) internal returns (address proxy) {
        assembly {
            proxy := create2(0x0, add(0x20, bytecode), mload(bytecode), salt)
        }
        require(proxy != address(0), "CreateFailed");
    }

    function _getPoolAddress(
        string memory name,
        string memory symbol,
        address collateralToken,
        uint8 collateralDecimals
    ) internal view returns (address) {
        bytes memory byteCode = _getBytesCode(
            name,
            symbol,
            collateralToken,
            collateralDecimals
        );
        bytes32 salt = _getProxyId(
            name,
            symbol,
            collateralToken,
            collateralDecimals
        );
        return _getAddress(byteCode, salt);
    }

    function _getAddress(
        bytes memory bytecode,
        bytes32 salt
    ) internal view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }
}
