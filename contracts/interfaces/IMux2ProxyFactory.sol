// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IMux2ProxyFactory {
    struct ProxyCallParams {
        uint256 projectId;
        address collateralToken;
        address assetToken;
        bool isLong;
        bytes32 referralCode;
        uint256 value;
        bytes proxyCallData;
    }

    function transferToken2(
        uint256 projectId,
        address account,
        address collateralToken,
        address assetToken,
        bool isLong,
        address token,
        uint256 amount
    ) external payable;

    function wrapAndTransferNative2(
        uint256 projectId,
        address account,
        address collateralToken,
        address assetToken,
        bool isLong,
        uint256 amount
    ) external payable;

    function muxFunctionCall(bytes memory muxCallData, uint256 value) external payable;

    function mux3PositionCall(
        address collateralToken,
        uint256 collateralAmount,
        bytes memory positionOrderCallData,
        uint256 initialLeverage, // 0 = ignore
        uint256 gas // 0 = ignore
    ) external payable;

    function proxyFunctionCall2(address account, ProxyCallParams calldata params) external payable;

    function cancelMuxOrder(address account, uint64 orderId) external;
}
