// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

import "../libraries/LibEthUnwrapper.sol";
import "../libraries/LibUniswap.sol";
import { Path } from "../libraries/LibUniswapPath.sol";
import "../interfaces/IErrors.sol";
import "../interfaces/ISwapper.sol";

/**
 * @notice Swapper is used to swap tokens (usually trading profits) into another token (usually a trader's collateral)
 *
 *         We may integrate with different DeFi protocols to provide better liquidity. However, regardless of the liquidity source,
 *         if the slippage does not meet trader's requirements, we will skip the swap.
 */
contract Swapper is Ownable2StepUpgradeable, ISwapper, IErrors {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 constant MIN_PATH_LENGTH = 20 + 3 + 20;

    /**
     * @notice The WETH token address used for ETH wrapping/unwrapping
     */
    address public weth;

    /**
     * @notice The Uniswap V3 Router contract used for token swaps
     */
    ISwapRouter public uniswapRouter;

    /**
     * @notice The Uniswap V3 Quoter contract used for price quotes
     */
    IQuoter public uniswapQuoter;

    mapping(bytes32 => bytes[]) internal swapPaths;

    event UniswapRouterSet(address uniswapRouter);
    event UniswapQuoterSet(address uniswapQuoter);
    event SetSwapPath(address tokenIn, address tokenOut, bytes[] paths);
    event MissingSwapPath(address tokenIn, address tokenOut);
    event AppendSwapPath(address tokenIn, address tokenOut, bytes path);
    event TransferOut(address token, uint256 amount, bool isUnwrapped);
    event SwapSuccess(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event SwapFailed(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        bool quoteSuccess,
        uint256 quoteBestOutAmount,
        bool swapSuccess,
        uint256 swapAmountOut
    );

    receive() external payable {
        // only weth can send ETH to this contract, to prevent unexpected ether transfers
        require(msg.sender == weth, "Swapper::INVALID_SENDER");
    }

    /**
     * @notice Initializes the Swapper contract
     * @param weth_ The WETH token address
     * @param uniswapRouter_ The Uniswap V3 Router address
     * @param uniswapQuoter_ The Uniswap V3 Quoter address
     * @dev Can only be called once due to initializer modifier
     */
    function initialize(address weth_, address uniswapRouter_, address uniswapQuoter_) external initializer {
        __Ownable_init();

        weth = weth_;
        _setUniswap(uniswapRouter_);
        _setUniswapQuoter(uniswapQuoter_);
    }

    /**
     * @notice Sets a new Uniswap Router address
     * @param _uniswapRouter The new router address
     */
    function setUniswapRouter(address _uniswapRouter) external onlyOwner {
        _setUniswap(_uniswapRouter);
    }

    /**
     * @notice Sets a new Uniswap Quoter address
     * @param _uniswapQuoter The new quoter address
     */
    function setUniswapQuoter(address _uniswapQuoter) external onlyOwner {
        _setUniswapQuoter(_uniswapQuoter);
    }

    /**
     * @notice Sets multiple swap paths for a token pair.
     *         Quoter will calculate among all possible paths to find the best one.
     *         This method will `REPLACE` all existing paths for the given token.
     *         Use `appendSwapPath` to add single path.
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param paths Array of encoded swap paths, see `Path.sol` for details
     *              Each path must be valid and have matching input/output tokens
     */
    function setSwapPath(address tokenIn, address tokenOut, bytes[] memory paths) external onlyOwner {
        for (uint256 i = 1; i < paths.length; i++) {
            _verifyPathInOut(tokenIn, tokenOut, paths[i]);
        }
        swapPaths[_encodeTokenPair(tokenIn, tokenOut)] = paths;
        emit SetSwapPath(tokenIn, tokenOut, paths);
    }

    function listSwapPath(
        address tokenIn,
        address tokenOut,
        uint256 begin,
        uint256 end
    ) external view returns (bytes[] memory ret) {
        bytes[] storage paths = swapPaths[_encodeTokenPair(tokenIn, tokenOut)];
        if (begin >= paths.length) {
            return new bytes[](0);
        }
        if (end > paths.length) {
            end = paths.length;
        }
        ret = new bytes[](end - begin);
        for (uint256 i = begin; i < end; i++) {
            ret[i - begin] = paths[i];
        }
    }

    /**
     * @notice Adds a new swap path for a token pair
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param path The encoded swap path to add, path must be valid and have matching input/output tokens
     */
    function appendSwapPath(address tokenIn, address tokenOut, bytes memory path) external onlyOwner {
        _verifyPathInOut(tokenIn, tokenOut, path);
        swapPaths[_encodeTokenPair(tokenIn, tokenOut)].push(path);
        emit AppendSwapPath(tokenIn, tokenOut, path);
    }

    /**
     * @notice Swaps tokens. If the swap fails or if tokenOut is same as tokenIn/zero, transfers tokenIn instead.
     * @param tokenIn The address of the input token
     * @param amountIn The amount of input tokens to swap
     * @param tokenOut The address of the output token (use address(0) to skip swap)
     * @param minAmountOut The minimum amount of output tokens required for the swap
     * @param receiver The address that will receive the output tokens
     * @param isUnwrapWeth If true and output is WETH, unwraps to ETH before transfer
     * @return bool Returns true if swap was successful, false otherwise
     * @return uint256 The amount of tokens transferred to receiver (either amountOut if swapped, or amountIn if not)
     */
    function swapAndTransfer(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        address receiver,
        bool isUnwrapWeth
    ) external returns (bool, uint256) {
        // no swap needed
        if (tokenOut == address(0) || tokenOut == tokenIn) {
            _transfer(tokenIn, amountIn, isUnwrapWeth, receiver);
            return (false, amountIn);
        }
        // path not found
        bytes[] memory paths = swapPaths[_encodeTokenPair(tokenIn, tokenOut)];
        if (paths.length == 0) {
            emit MissingSwapPath(tokenIn, tokenOut);
            _transfer(tokenIn, amountIn, isUnwrapWeth, receiver);
            return (false, amountIn);
        }
        // quote
        (bool quoteSuccess, uint256 bestPathIndex, uint256 bestOutAmount) = LibUniswap.quote(
            uniswapQuoter,
            paths,
            amountIn
        );
        if (!quoteSuccess || bestOutAmount < minAmountOut) {
            emit SwapFailed(tokenIn, amountIn, tokenOut, minAmountOut, quoteSuccess, bestOutAmount, false, 0);
            _transfer(tokenIn, amountIn, isUnwrapWeth, receiver);
            return (false, amountIn);
        }
        // swap
        (uint256 amountOut, bool swapSuccess) = LibUniswap.swap(
            uniswapRouter,
            paths[bestPathIndex],
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut
        );
        if (!swapSuccess) {
            emit SwapFailed(
                tokenIn,
                amountIn,
                tokenOut,
                minAmountOut,
                quoteSuccess,
                bestOutAmount,
                swapSuccess,
                amountOut
            );
            _transfer(tokenIn, amountIn, isUnwrapWeth, receiver);
            return (false, amountIn);
        }
        // transfer swapped tokens
        require(
            IERC20MetadataUpgradeable(tokenOut).balanceOf(address(this)) >= amountOut,
            "Swapper::INVALID_TOKEN_OUT"
        );
        _transfer(tokenOut, amountOut, isUnwrapWeth, receiver);
        emit SwapSuccess(tokenIn, amountIn, tokenOut, amountOut);
        return (true, amountOut);
    }

    /**
     * @notice Try to query the out amount for a given path
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens
     * @return path The encoded swap path that gives the best output
     * @return quoteSuccess Whether the quote was successful
     * @return bestPathIndex Index of the best path in the paths array
     * @return bestOutAmount The amount of output tokens for the best path
     */
    function quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (bytes memory path, bool quoteSuccess, uint256 bestPathIndex, uint256 bestOutAmount) {
        bytes[] memory paths = swapPaths[_encodeTokenPair(tokenIn, tokenOut)];
        require(paths.length > 0, "Swapper::NO_PATH_SET");
        (quoteSuccess, bestPathIndex, bestOutAmount) = LibUniswap.quote(uniswapQuoter, paths, amountIn);
        if (quoteSuccess) {
            path = paths[bestPathIndex];
        }
    }

    function _verifyPathInOut(address tokenIn, address tokenOut, bytes memory path) internal pure {
        require(tokenIn != tokenOut, "Swapper::INVALID_PATH");
        require(path.length >= MIN_PATH_LENGTH, "Swapper::INVALID_PATH");
        (address realTokenIn, , ) = Path.decodeFirstPool(path);
        while (Path.hasMultiplePools(path)) {
            path = Path.skipToken(path);
        }
        (, address realTokenOut, ) = Path.decodeFirstPool(path);
        require(realTokenIn == tokenIn && realTokenOut == tokenOut, "Swapper::INVALID_PATH");
    }

    function _transfer(address token, uint256 amount, bool isUnwrapWeth, address receiver) internal {
        if (token == weth && isUnwrapWeth) {
            bool success = LibEthUnwrapper.unwrap(weth, payable(receiver), amount);
            emit TransferOut(weth, amount, success);
        } else {
            IERC20Upgradeable(token).safeTransfer(receiver, amount);
            emit TransferOut(token, amount, false);
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

    function _encodeTokenPair(address tokenIn, address tokenOut) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }
}
