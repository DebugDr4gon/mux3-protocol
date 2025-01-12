// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault as IBalancer2Vault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset as IBalancer2Asset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "../../libraries/LibTypeCast.sol";

contract MockBalancer2 {
    using LibTypeCast for uint256;

    IERC20 usdc;
    IERC20 weth;
    IERC20 wbtc;
    IERC20 arb;
    uint256 dummyValue;

    constructor(address usdc_, address weth_, address wbtc_, address arb_) {
        usdc = IERC20(usdc_);
        weth = IERC20(weth_);
        wbtc = IERC20(wbtc_);
        arb = IERC20(arb_);
    }

    function queryBatchSwap(
        IBalancer2Vault.SwapKind kind,
        IBalancer2Vault.BatchSwapStep[] memory swaps,
        IBalancer2Asset[] memory assets,
        IBalancer2Vault.FundManagement memory
    ) external returns (int256[] memory assetDeltas) {
        dummyValue += 1; // queryBatchSwap is not a view function, in order to simulate this, we modify the state
        require(kind == IBalancer2Vault.SwapKind.GIVEN_IN, "Unsupported swap kind");
        assetDeltas = _swapWithPools(swaps, assets);
    }

    function batchSwap(
        IBalancer2Vault.SwapKind kind,
        IBalancer2Vault.BatchSwapStep[] memory swaps,
        IBalancer2Asset[] memory assets,
        IBalancer2Vault.FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory assetDeltas) {
        require(block.timestamp <= deadline, "Errors.SWAP_DEADLINE");
        require(assets.length == limits.length, "Errors.INPUT_LENGTH_MISMATCH");
        require(kind == IBalancer2Vault.SwapKind.GIVEN_IN, "Unsupported swap kind");
        assetDeltas = _swapWithPools(swaps, assets);

        for (uint256 i = 0; i < assets.length; ++i) {
            IBalancer2Asset asset = assets[i];
            int256 delta = assetDeltas[i];
            require(delta <= limits[i], "Errors.SWAP_LIMIT");
            if (delta > 0) {
                uint256 toReceive = uint256(delta);
                IERC20(address(asset)).transferFrom(funds.sender, address(this), toReceive);
            } else if (delta < 0) {
                uint256 toSend = uint256(-delta);
                IERC20(address(asset)).transfer(funds.recipient, toSend);
            }
        }
    }

    function _swapWithPools(
        IBalancer2Vault.BatchSwapStep[] memory swaps,
        IBalancer2Asset[] memory assets
    ) internal view returns (int256[] memory assetDeltas) {
        assetDeltas = new int256[](assets.length);
        IBalancer2Vault.BatchSwapStep memory batchSwapStep;
        IERC20 previousTokenCalculated;
        uint256 previousAmountCalculated;
        for (uint256 i = 0; i < swaps.length; ++i) {
            batchSwapStep = swaps[i];

            bool withinBounds = batchSwapStep.assetInIndex < assets.length &&
                batchSwapStep.assetOutIndex < assets.length;
            require(withinBounds, "Errors.OUT_OF_BOUNDS");

            IERC20 tokenIn = IERC20(address(assets[batchSwapStep.assetInIndex]));
            IERC20 tokenOut = IERC20(address(assets[batchSwapStep.assetOutIndex]));
            require(tokenIn != tokenOut, "Errors.CANNOT_SWAP_SAME_TOKEN");

            if (batchSwapStep.amount == 0) {
                require(i > 0, "Errors.UNKNOWN_AMOUNT_IN_FIRST_SWAP");
                bool usingPreviousToken = previousTokenCalculated == tokenIn;
                require(usingPreviousToken, "Errors.MALCONSTRUCTED_MULTIHOP_SWAP");
                batchSwapStep.amount = previousAmountCalculated;
            }

            // (previousAmountCalculated, amountIn, amountOut) = _swapWithPool(tokenIn, tokenOut, batchSwapStep.amount)
            uint256 amountIn = batchSwapStep.amount;
            uint256 amountOut;
            if (tokenIn == weth && tokenOut == usdc) {
                // assume 3000
                previousAmountCalculated = amountOut = (amountIn * 3000) / 1e12;
            } else if (tokenIn == usdc && tokenOut == weth) {
                // assume 1/3000
                previousAmountCalculated = amountOut = (amountIn * 1e12) / 3000;
            } else if (tokenIn == wbtc && tokenOut == usdc) {
                // assume 50000
                previousAmountCalculated = amountOut = (amountIn * 50000) / 1e10;
            } else if (tokenIn == usdc && tokenOut == wbtc) {
                // assume 1/50000
                previousAmountCalculated = amountOut = (amountIn * 1e2) / 50000;
            } else if (tokenIn == arb && tokenOut == usdc) {
                // assume 1
                previousAmountCalculated = amountOut = (amountIn * 1) / 1e12;
            } else if (tokenIn == usdc && tokenOut == arb) {
                // assume 1/1
                previousAmountCalculated = amountOut = (amountIn * 1e12) / 1;
            } else {
                revert("Unsupported pair");
            }

            previousTokenCalculated = tokenOut;
            assetDeltas[batchSwapStep.assetInIndex] = assetDeltas[batchSwapStep.assetInIndex] + amountIn.toInt256();
            assetDeltas[batchSwapStep.assetOutIndex] = assetDeltas[batchSwapStep.assetOutIndex] - amountOut.toInt256();
        }
    }
}
