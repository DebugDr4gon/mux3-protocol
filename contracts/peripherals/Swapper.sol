// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "../libraries/LibEthUnwrapper.sol";
import "../libraries/LibUniswap3.sol";
import "../libraries/LibBalancer2.sol";
import "../interfaces/IErrors.sol";
import "../interfaces/ISwapper.sol";
import "../libraries/LibBytes.sol";

/**
 * @notice Swapper is used to swap tokens (usually trading profits) into another token (usually a trader's collateral)
 *
 *         We may integrate with different DeFi protocols to provide better liquidity. However, regardless of the liquidity source,
 *         if the slippage does not meet trader's requirements, we will skip the swap.
 */
contract Swapper is AccessControlEnumerableUpgradeable, ISwapper, IErrors {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum Protocol {
        Uniswap3,
        Balancer2
    }

    /**
     * @notice The WETH token address used for ETH wrapping/unwrapping
     */
    address public weth;

    /**
     * @notice The Uniswap V3 Router
     */
    address public uniswap3Router;

    /**
     * @notice The Uniswap V3 Quoter
     */
    address public uniswap3Quoter;

    mapping(bytes32 => bytes[]) private _reserved1;

    /**
     * @dev Mapping of token pairs to swap paths
     *      See `decodePath` for details.
     */
    mapping(bytes32 => bytes[]) internal swapPaths;

    /**
     * @notice The Balancer V2 Vault
     */
    address public balancer2Vault;

    event SetUniswap3(address uniswap3Router, address uniswap3Quoter);
    event SetBalancer2(address balancer2Vault);
    event SetSwapPath(address tokenIn, address tokenOut, bytes[] paths);
    event AppendSwapPath(address tokenIn, address tokenOut, bytes path);
    event MissingSwapPath(address tokenIn, address tokenOut);
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
     */
    function initialize(address weth_) external initializer {
        __AccessControlEnumerable_init();

        weth = weth_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Sets a new Uniswap Router, Quoter address
     * @param uniswap3Router_ The new router address
     * @param uniswap3Quoter_ The new quoter address
     */
    function setUniswap3(address uniswap3Router_, address uniswap3Quoter_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(uniswap3Router_ != address(0), "Swapper::INVALID_UNISWAP_ROUTER");
        require(uniswap3Quoter_ != address(0), "Swapper::INVALID_UNISWAP_QUOTER");
        uniswap3Router = uniswap3Router_;
        uniswap3Quoter = uniswap3Quoter_;
        emit SetUniswap3(uniswap3Router_, uniswap3Quoter_);
    }

    /**
     * @notice Sets a new Balancer V2 Vault address
     * @param balancer2Vault_ The new vault address
     */
    function setBalancer2(address balancer2Vault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(balancer2Vault_ != address(0), "Swapper::INVALID_BALANCER_VAULT");
        balancer2Vault = balancer2Vault_;
        emit SetBalancer2(balancer2Vault_);
    }

    /**
     * @notice Sets multiple swap paths for a token pair.
     *         Quoter will calculate among all possible paths to find the best one.
     *         This method will `REPLACE` all existing paths for the given token.
     *         Use `appendSwapPath` to add single path.
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param paths A list of encoded swap paths. See `decodePath` for details.
     */
    function setSwapPath(
        address tokenIn,
        address tokenOut,
        bytes[] memory paths
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < paths.length; i++) {
            _verifyPath(tokenIn, tokenOut, paths[i]);
        }
        swapPaths[encodeTokenPair(tokenIn, tokenOut)] = paths;
        emit SetSwapPath(tokenIn, tokenOut, paths);
    }

    /**
     * @notice Adds a new swap path for a token pair
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param path The encoded swap path to add, path must be valid and have matching input/output tokens
     */
    function appendSwapPath(
        address tokenIn,
        address tokenOut,
        bytes memory path
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _verifyPath(tokenIn, tokenOut, path);
        swapPaths[encodeTokenPair(tokenIn, tokenOut)].push(path);
        emit AppendSwapPath(tokenIn, tokenOut, path);
    }

    function listSwapPath(
        address tokenIn,
        address tokenOut,
        uint256 begin,
        uint256 end
    ) external view returns (bytes[] memory ret) {
        bytes[] storage paths = swapPaths[encodeTokenPair(tokenIn, tokenOut)];
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
     * @notice Try to query the out amount for a given path
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens
     * @return quoteSuccess Whether the quote was successful
     * @return bestPathIndex Index of the best path in the paths array
     * @return bestPath The encoded swap path that gives the best output
     * @return bestOutAmount The amount of output tokens for the best path
     */
    function quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (bool quoteSuccess, uint256 bestPathIndex, bytes memory bestPath, uint256 bestOutAmount) {
        return _quote(tokenIn, tokenOut, amountIn);
    }

    /**
     * @notice Swaps tokens. If the swap fails or if tokenOut is same as tokenIn, transfers tokenIn instead.
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
        bytes[] memory paths = swapPaths[encodeTokenPair(tokenIn, tokenOut)];
        if (paths.length == 0) {
            emit MissingSwapPath(tokenIn, tokenOut);
            _transfer(tokenIn, amountIn, isUnwrapWeth, receiver);
            return (false, amountIn);
        }
        // quote
        (bool quoteSuccess, , bytes memory bestPath, uint256 bestOutAmount) = _quote(tokenIn, tokenOut, amountIn);
        if (!quoteSuccess || bestOutAmount < minAmountOut) {
            emit SwapFailed(tokenIn, amountIn, tokenOut, minAmountOut, quoteSuccess, bestOutAmount, false, 0);
            _transfer(tokenIn, amountIn, isUnwrapWeth, receiver);
            return (false, amountIn);
        }
        // swap
        (bool swapSuccess, uint256 amountOut) = _swap(bestPath, tokenIn, tokenOut, amountIn, minAmountOut);
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
     * @notice Encodes a token pair into a bytes32 hash
     */
    function encodeTokenPair(address tokenIn, address tokenOut) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    /**
     * @notice Decodes a swap path, where a path is:
     *      * For Uniswap3:  | 00 | token1 | fee1 | token2 | fee2 | token3 |
     *      * For Balancer2: | 01 | abi.encode((assets, swaps)) |
     */
    function decodePath(bytes memory path) public pure returns (Protocol protocol, bytes memory rawPath) {
        require(path.length >= 1, "Swapper::INVALID_PATH");
        protocol = Protocol(uint8(path[0]));
        rawPath = LibBytes.slice(path, 1, path.length - 1);
    }

    function _quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (bool quoteSuccess, uint256 bestPathIndex, bytes memory bestPath, uint256 bestOutAmount) {
        bytes[] memory paths = swapPaths[encodeTokenPair(tokenIn, tokenOut)];
        require(paths.length > 0, "Swapper::NO_PATH_SET");
        for (uint256 i = 0; i < paths.length; i++) {
            bool localSuccess;
            uint256 localAmountOut;
            (Protocol protocol, bytes memory rawPath) = decodePath(paths[i]);
            if (protocol == Protocol.Uniswap3) {
                (localSuccess, localAmountOut) = LibUniswap3.quote(uniswap3Quoter, rawPath, amountIn);
            } else if (protocol == Protocol.Balancer2) {
                (localSuccess, localAmountOut) = LibBalancer2.quote(balancer2Vault, rawPath, amountIn);
            }
            if (localSuccess && localAmountOut > bestOutAmount) {
                quoteSuccess = true;
                bestPathIndex = i;
                bestOutAmount = localAmountOut;
            }
        }
        if (quoteSuccess) {
            bestPath = paths[bestPathIndex];
        }
    }

    function _swap(
        bytes memory bestPath,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (bool swapSuccess, uint256 amountOut) {
        (Protocol protocol, bytes memory rawPath) = decodePath(bestPath);
        if (protocol == Protocol.Uniswap3) {
            (swapSuccess, amountOut) = LibUniswap3.swap(
                uniswap3Router,
                rawPath,
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut
            );
        } else if (protocol == Protocol.Balancer2) {
            (swapSuccess, amountOut) = LibBalancer2.swap(
                balancer2Vault,
                rawPath,
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut
            );
        }
    }

    function _verifyPath(address tokenIn, address tokenOut, bytes memory path) internal pure {
        require(tokenIn != tokenOut, "Swapper::INVALID_PATH");
        (Protocol protocol, bytes memory rawPath) = decodePath(path);
        bool valid;
        if (protocol == Protocol.Uniswap3) {
            valid = LibUniswap3.isValidPath(tokenIn, tokenOut, rawPath);
        } else if (protocol == Protocol.Balancer2) {
            valid = LibBalancer2.isValidPath(tokenIn, tokenOut, rawPath);
        }
        require(valid, "Swapper::INVALID_PATH");
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
}
