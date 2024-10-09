// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "../../core/management/FacetManagement.sol";
import "../../core/trade/PositionAccount.sol";

contract TestPositionManager is PositionAccount, FacetManagement {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    mapping(bytes32 => uint256) private _mockCache;

    // only used in unit test
    function setTrustedCaller(address user) external {
        _grantRole(DEFAULT_ADMIN_ROLE, user);
    }

    function setMockPool(address pool) external {
        _collateralPoolList.add(pool);
    }

    function priceOf(address token) internal view virtual returns (uint256) {
        return _priceOf(bytes32(bytes20(token)));
    }

    function priceOf(bytes32 id) internal view virtual returns (uint256) {
        return _priceOf(id);
    }

    function _priceOf(
        bytes32 id
    ) internal view virtual override returns (uint256) {
        return _mockCache[id];
    }

    function setMockPrice(bytes32 key, uint256 price) external {
        _mockCache[key] = price;
    }

    function updatePositionFee(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) external {
        _updatePositionFee(positionId, marketId, size);
    }

    function collateralValue(
        bytes32 positionId
    ) external view returns (uint256) {
        return _collateralValue(positionId);
    }

    function positionValue(bytes32 positionId) external view returns (uint256) {
        return _positionValue(positionId);
    }

    function positionMargin(
        bytes32 positionId
    ) external view returns (uint256) {
        return _positionMargin(positionId);
    }

    function isInitialMarginSafe(
        bytes32 positionId
    ) external view returns (bool) {
        return _isInitialMarginSafe(positionId);
    }

    function isMaintenanceMarginSafe(
        bytes32 positionId
    ) external view returns (bool) {
        return _isMaintenanceMarginSafe(positionId);
    }

    function isLeverageSafe(bytes32 positionId) external view returns (bool) {
        return _isLeverageSafe(positionId);
    }

    function borrowingFeeUsd(
        bytes32 positionId,
        bytes32 marketId,
        uint256 size
    ) external view returns (uint256) {
        return _borrowingFeeUsd(positionId, marketId, size);
    }
}
