// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

import "../libraries/LibEthUnwrapper.sol";
import "../libraries/LibUniswap.sol";
import "../interfaces/IErrors.sol";

contract Swapper is OwnableUpgradeable, IErrors {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public WETH;
    ISwapRouter public uniswapRouter;
    IQuoter public uniswapQuoter;

    mapping(address => bytes[]) internal swapPaths;

    event UniswapRouterSet(address uniswapRouter);
    event UniswapQuoterSet(address uniswapQuoter);
    event SetSwapPath(address tokenIn, bytes[] paths);
    event AppendSwapPath(address tokenIn, bytes path);

    receive() external payable {
        require(msg.sender == WETH, "Swapper::INVALID_SENDER");
    }

    function initialize(address _WETH, address _uniswapRouter, address _uniswapQuoter) external initializer {
        __Ownable_init();

        WETH = _WETH;
        _setUniswap(_uniswapRouter);
        _setUniswapQuoter(_uniswapQuoter);
    }

    function setUniswapRouter(address _uniswapRouter) external onlyOwner {
        _setUniswap(_uniswapRouter);
    }

    function setUniswapQuoter(address _uniswapQuoter) external onlyOwner {
        _setUniswapQuoter(_uniswapQuoter);
    }

    function setSwapPath(address tokenIn, bytes[] memory paths) external onlyOwner {
        swapPaths[tokenIn] = paths;
        emit SetSwapPath(tokenIn, paths);
    }

    function appendSwapPath(address tokenIn, bytes memory path) external onlyOwner {
        require(path.length > 0, "Swapper::INVALID_PATH");
        swapPaths[tokenIn].push(path);
        emit AppendSwapPath(tokenIn, path);
    }

    function swapAndTransfer(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        address receiver,
        bool isUnwrapWeth
    ) external {
        bytes[] memory paths = swapPaths[tokenIn];
        require(paths.length > 0, EssentialConfigNotSet("SWAP_PATH"));
        (uint256 bestPathIndex, uint256 bestOutAmount) = LibUniswap.quote(uniswapQuoter, paths, amountIn);

        if (bestOutAmount >= minAmountOut) {
            (uint256 amountOut, bool success) = LibUniswap.swap(
                uniswapRouter,
                paths[bestPathIndex],
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut
            );
            if (success) {
                _transfer(tokenOut, amountOut, isUnwrapWeth, receiver);
                return;
            }
        }
        _transfer(tokenIn, amountIn, isUnwrapWeth, receiver);
    }

    function _transfer(address token, uint256 amount, bool isUnwrapWeth, address receiver) internal {
        if (token == WETH && isUnwrapWeth) {
            LibEthUnwrapper.unwrap(WETH, payable(receiver), amount);
        } else {
            IERC20Upgradeable(token).safeTransfer(receiver, amount);
        }
    }

    function _setUniswap(address _uniswapRouter) internal {
        require(_uniswapRouter != address(0), "Swapper::INVALID_UNISWAP_ROUTER");
        uniswapRouter = ISwapRouter(_uniswapRouter);
        emit UniswapRouterSet(_uniswapRouter);
    }

    function _setUniswapQuoter(address _uniswapQuoter) internal {
        require(_uniswapQuoter != address(0), "Swapper::INVALID_UNISWAP_QUOTER");
        uniswapQuoter = IQuoter(_uniswapQuoter);
        emit UniswapQuoterSet(_uniswapQuoter);
    }
}
