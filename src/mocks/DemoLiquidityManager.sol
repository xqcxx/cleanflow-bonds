// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20} from "../core/TokenUtils.sol";

/// @notice Minimal ERC-20 position manager for local and testnet demonstrations.
contract DemoLiquidityManager is SafeCallback {
    using BalanceDeltaLibrary for BalanceDelta;

    struct Operation {
        PoolKey key;
        ModifyLiquidityParams params;
        address payer;
    }

    error ReentrantCall();
    error NotExecuting();
    error NativeCurrencyUnsupported();
    error TokenTransferFailed();

    bool private executing;

    constructor(IPoolManager poolManager_) SafeCallback(poolManager_) {}

    function addLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bytes32 salt
    ) external {
        if (executing) revert ReentrantCall();
        if (Currency.unwrap(key.currency0) == address(0) || Currency.unwrap(key.currency1) == address(0)) {
            revert NativeCurrencyUnsupported();
        }
        executing = true;
        poolManager.unlock(
            abi.encode(
                Operation({
                    key: key,
                    params: ModifyLiquidityParams({
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        liquidityDelta: int256(uint256(liquidity)),
                        salt: salt
                    }),
                    payer: msg.sender
                })
            )
        );
        executing = false;
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        if (!executing) revert NotExecuting();
        Operation memory operation = abi.decode(data, (Operation));
        (BalanceDelta delta,) = poolManager.modifyLiquidity(operation.key, operation.params, "");
        _settle(operation.key.currency0, delta.amount0(), operation.payer);
        _settle(operation.key.currency1, delta.amount1(), operation.payer);
        return bytes("");
    }

    function _settle(Currency currency, int128 delta, address payer) private {
        if (delta >= 0) return;
        uint256 amount = uint256(-int256(delta));
        poolManager.sync(currency);
        if (!IERC20(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount)) {
            revert TokenTransferFailed();
        }
        poolManager.settle();
    }
}
