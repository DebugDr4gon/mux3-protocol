// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IMux3RebalancerCallback.sol";
import "../../interfaces/IFacetReader.sol";
import "../../interfaces/IOrderBook.sol";

contract TestRebalancer is IMux3RebalancerCallback {
    using SafeERC20 for IERC20;

    address _core;
    address _orderBook;

    constructor(address core_, address orderBook_) {
        _core = core_;
        _orderBook = orderBook_;
    }

    function placeOrder(RebalanceOrderParams memory args) external {
        IOrderBook(_orderBook).placeRebalanceOrder(args);
    }

    function mux3RebalanceCallback(
        address pool,
        address token0,
        address token1,
        uint256 rawAmount0,
        uint256 minRawAmount1,
        bytes memory userData
    ) external {
        token0;
        rawAmount0;
        require(IFacetReader(_core).getCollateralPool(pool), "Pool not found");
        require(keccak256(userData) == keccak256(bytes("TestRebalancer.userData")), "userData mismatch");
        IERC20(token1).transfer(pool, minRawAmount1);
    }

    function cancelOrder(uint64 orderId) external {
        IOrderBook(_orderBook).cancelOrder(orderId);
    }
}
