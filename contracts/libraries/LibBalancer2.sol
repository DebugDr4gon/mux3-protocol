// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IVault as IBalancer2Vault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset as IBalancer2Asset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "../interfaces/ISwapper.sol";
import "../libraries/LibTypeCast.sol";

library LibBalancer2 {
    struct Args {
        IBalancer2Asset[] assets;
        IBalancer2Vault.BatchSwapStep[] swaps;
    }

    // we always assume assets[0] is assetIn, assets[-1] is assetOut
    function isValidPath(address tokenIn, address tokenOut, bytes memory path) internal pure returns (bool) {
        if (tokenIn == tokenOut) {
            return false;
        }
        Args memory args = abi.decode(path, (Args));
        if (args.assets.length < 2) {
            return false;
        }
        if (address(args.assets[0]) != tokenIn) {
            return false;
        }
        if (address(args.assets[args.assets.length - 1]) != tokenOut) {
            return false;
        }
        if (args.swaps.length < 1) {
            return false;
        }
        address previousToken = tokenIn;
        for (uint256 i = 0; i < args.swaps.length; i++) {
            IBalancer2Vault.BatchSwapStep memory step = args.swaps[i];
            if (step.amount != 0) {
                // make sure amount is 0 as a template
                return false;
            }
            if (step.userData.length != 0) {
                // make sure userData is empty as a template
                return false;
            }
            if (step.assetInIndex >= args.assets.length) {
                return false;
            }
            if (step.assetOutIndex >= args.assets.length) {
                return false;
            }
            if (address(args.assets[step.assetInIndex]) != previousToken) {
                return false;
            }
            previousToken = address(args.assets[step.assetOutIndex]);
        }
        return true;
    }

    function quote(
        address vault,
        bytes memory path,
        uint256 amountIn
    ) internal returns (bool success, uint256 amountOut) {
        require(address(vault) != address(0), "Swapper::balancer2Vault not set");
        Args memory args = abi.decode(path, (Args));
        // we always assume assets[0] is assetIn, assets[-1] is assetOut
        args.swaps[0].amount = amountIn;
        // fund will come from the contract
        IBalancer2Vault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;
        // the asset out will have a negative Vault delta (the assets are coming out of the Pool and the user is
        // receiving them), so make it positive to match the `swap` interface.
        try
            IBalancer2Vault(vault).queryBatchSwap(IBalancer2Vault.SwapKind.GIVEN_IN, args.swaps, args.assets, funds)
        returns (int256[] memory assetDeltas) {
            if (assetDeltas[args.assets.length - 1] <= 0) {
                success = true;
                amountOut = LibTypeCast.negInt256(assetDeltas[args.assets.length - 1]);
            } else {
                // probably insufficient liquidity, not a big deal
                emit ISwapper.BrokenBalancer2Path(path, amountIn);
            }
        } catch {
            // probably insufficient liquidity, not a big deal
            emit ISwapper.BrokenBalancer2Path(path, amountIn);
        }
    }

    function swap(
        address vault,
        bytes memory path,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (bool success, uint256 amountOut) {
        require(address(vault) != address(0), "Swapper::balancer2Vault not set");
        Args memory args = abi.decode(path, (Args));
        // we always assume assets[0] is assetIn, assets[-1] is assetOut
        args.swaps[0].amount = amountIn;
        // approve
        SafeERC20Upgradeable.forceApprove(IERC20Upgradeable(tokenIn), address(vault), amountIn);
        // fund will come from the contract
        IBalancer2Vault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;
        // the asset out will have a negative Vault delta (the assets are coming out of the Pool and the user is
        // receiving them), so make it positive to match the `swap` interface.
        int256[] memory limits = new int256[](args.assets.length); // no limits
        limits[0] = int256(amountIn);
        limits[limits.length - 1] = -LibTypeCast.toInt256(minAmountOut);
        uint256 deadline = block.timestamp; // no deadline
        try
            IBalancer2Vault(vault).batchSwap(
                IBalancer2Vault.SwapKind.GIVEN_IN,
                args.swaps,
                args.assets,
                funds,
                limits,
                deadline
            )
        returns (int256[] memory assetDeltas) {
            if (assetDeltas[args.assets.length - 1] <= 0) {
                success = true;
                amountOut = LibTypeCast.negInt256(assetDeltas[args.assets.length - 1]);
            }
        } catch {}
        emit ISwapper.Balancer2Call(tokenIn, tokenOut, amountIn, amountOut);
    }
}
