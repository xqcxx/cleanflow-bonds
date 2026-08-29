// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-hooks-public/base/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {CleanFlowTypes} from "../core/CleanFlowTypes.sol";
import {CleanFlowController} from "../core/CleanFlowController.sol";

contract CleanFlowHook is BaseHook {
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint24 public constant STANDARD_FEE = 3_000;
    uint24 public constant PROTECTED_FEE = 500;

    error Unauthorized();
    error InvalidHookData();
    error InvalidSwapDelta();

    CleanFlowController public immutable controller;
    address public immutable router;
    mapping(bytes32 authorizationId => int24 tick) private tickBefore;

    event ProtectedSwapExecuted(
        uint256 indexed sequence,
        bytes32 indexed executionId,
        address indexed executor,
        address trader,
        bytes32 poolId,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut,
        int24 tickBefore,
        int24 tickAfter,
        uint64 snapshotBlock
    );
    event ExecutorTradeObserved(
        uint256 indexed sequence,
        bytes32 indexed tradeId,
        address indexed executor,
        bytes32 poolId,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(IPoolManager poolManager_, CleanFlowController controller_, address router_)
        BaseHook(poolManager_)
    {
        if (address(controller_) == address(0) || router_ == address(0)) revert Unauthorized();
        controller = controller_;
        router = router_;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions.beforeSwap = true;
        permissions.afterSwap = true;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (sender != router || hookData.length != 32 || params.amountSpecified >= 0) revert Unauthorized();
        bytes32 authorizationId = abi.decode(hookData, (bytes32));
        uint256 amountIn = uint256(-params.amountSpecified);
        CleanFlowTypes.AuthorizationKind kind = controller.consumeAuthorization(
            authorizationId,
            PoolId.unwrap(key.toId()),
            params.zeroForOne,
            amountIn
        );
        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
        tickBefore[authorizationId] = currentTick;
        uint24 fee = kind == CleanFlowTypes.AuthorizationKind.Protected ? PROTECTED_FEE : STANDARD_FEE;
        return (
            this.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        if (sender != router || hookData.length != 32) revert Unauthorized();
        bytes32 authorizationId = abi.decode(hookData, (bytes32));
        (uint256 amountIn, uint256 amountOut) = _actualAmounts(params.zeroForOne, delta);
        (uint64 sequence, CleanFlowTypes.Authorization memory authorization) =
            controller.recordSwap(authorizationId, amountIn, amountOut);
        if (authorization.kind == CleanFlowTypes.AuthorizationKind.Protected) {
            (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
            CleanFlowTypes.Warranty memory warranty = controller.getWarranty(authorization.executionId);
            emit ProtectedSwapExecuted(
                sequence,
                authorization.executionId,
                authorization.executor,
                authorization.trader,
                authorization.poolId,
                authorization.zeroForOne,
                amountIn,
                amountOut,
                tickBefore[authorizationId],
                currentTick,
                warranty.snapshotBlock
            );
        } else if (authorization.kind == CleanFlowTypes.AuthorizationKind.Inventory) {
            emit ExecutorTradeObserved(
                sequence,
                authorization.executionId,
                authorization.executor,
                authorization.poolId,
                authorization.zeroForOne,
                amountIn,
                amountOut
            );
        } else {
            revert InvalidHookData();
        }
        delete tickBefore[authorizationId];
        return (this.afterSwap.selector, 0);
    }

    function _actualAmounts(bool zeroForOne, BalanceDelta delta)
        private
        pure
        returns (uint256 amountIn, uint256 amountOut)
    {
        int128 inputDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidSwapDelta();
        amountIn = uint256(-int256(inputDelta));
        amountOut = uint256(uint128(outputDelta));
    }
}
