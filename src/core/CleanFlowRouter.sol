// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {CleanFlowTypes} from "./CleanFlowTypes.sol";
import {CleanFlowController} from "./CleanFlowController.sol";
import {IERC20} from "./TokenUtils.sol";

contract CleanFlowRouter is SafeCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("CleanFlow Bonds");
    bytes32 private constant VERSION_HASH = keccak256("1");
    uint256 private constant SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    struct SwapOperation {
        PoolKey key;
        SwapParams params;
        bytes32 authorizationId;
        address payer;
        address recipient;
    }

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidMandate();
    error InvalidSignature();
    error NonceAlreadyUsed();
    error ExpiredMandate();
    error ReentrantCall();
    error NotExecuting();
    error NativeCurrencyUnsupported();
    error TokenTransferFailed();
    error InsufficientOutput();

    CleanFlowController public immutable controller;
    address public immutable owner;
    address public hook;
    bytes32 public configuredPoolId;
    bool private executing;

    mapping(address trader => mapping(uint64 nonce => bool)) public nonceUsed;

    event PoolConfigured(address indexed hook, bytes32 indexed poolId);
    event MandateExecuted(
        bytes32 indexed executionId,
        bytes32 indexed authorizationId,
        address indexed trader,
        address executor,
        uint256 amountIn,
        uint256 amountOut
    );
    event InventoryTradeExecuted(
        bytes32 indexed authorizationId,
        address indexed executor,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(IPoolManager poolManager_, CleanFlowController controller_) SafeCallback(poolManager_) {
        if (address(controller_) == address(0)) revert InvalidConfiguration();
        controller = controller_;
        owner = msg.sender;
    }

    function setPool(address hook_, bytes32 poolId_) external {
        if (
            msg.sender != owner || hook != address(0) || hook_ == address(0) || poolId_ == bytes32(0)
        ) revert Unauthorized();
        hook = hook_;
        configuredPoolId = poolId_;
        emit PoolConfigured(hook_, poolId_);
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    function mandateDigest(CleanFlowTypes.ExecutionMandate memory mandate) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), CleanFlowTypes.hashMandate(mandate)));
    }

    function executeProtected(
        PoolKey memory key,
        CleanFlowTypes.ExecutionMandate memory mandate,
        bytes calldata signature
    ) external returns (bytes32 executionId, uint256 amountOut) {
        if (executing) revert ReentrantCall();
        _validatePool(key);
        if (block.timestamp > mandate.deadline) revert ExpiredMandate();
        if (
            mandate.executor != msg.sender || mandate.trader == address(0) || mandate.recipient == address(0)
                || mandate.poolId != configuredPoolId || mandate.amountIn == 0 || mandate.warrantyTier != 1
        ) revert InvalidMandate();
        if (nonceUsed[mandate.trader][mandate.nonce]) revert NonceAlreadyUsed();

        bytes32 digest = mandateDigest(mandate);
        if (_recover(digest, signature) != mandate.trader) revert InvalidSignature();
        nonceUsed[mandate.trader][mandate.nonce] = true;
        executionId = digest;
        bytes32 authorizationId = controller.beginProtectedExecution(
            executionId,
            mandate.trader,
            mandate.executor,
            mandate.poolId,
            mandate.zeroForOne,
            mandate.amountIn
        );
        amountOut = _executeSwap(
            key,
            mandate.zeroForOne,
            mandate.amountIn,
            mandate.sqrtPriceLimitX96,
            authorizationId,
            mandate.trader,
            mandate.recipient
        );
        if (amountOut < mandate.minAmountOut) revert InsufficientOutput();
        emit MandateExecuted(
            executionId,
            authorizationId,
            mandate.trader,
            mandate.executor,
            mandate.amountIn,
            amountOut
        );
    }

    function executeExecutorTrade(
        PoolKey memory key,
        bool zeroForOne,
        uint128 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (bytes32 authorizationId, uint256 amountOut) {
        if (executing) revert ReentrantCall();
        _validatePool(key);
        authorizationId = controller.authorizeInventoryTrade(
            msg.sender,
            configuredPoolId,
            zeroForOne,
            amountIn
        );
        amountOut = _executeSwap(
            key,
            zeroForOne,
            amountIn,
            sqrtPriceLimitX96,
            authorizationId,
            msg.sender,
            msg.sender
        );
        emit InventoryTradeExecuted(authorizationId, msg.sender, amountIn, amountOut);
    }

    function _executeSwap(
        PoolKey memory key,
        bool zeroForOne,
        uint128 amountIn,
        uint160 sqrtPriceLimitX96,
        bytes32 authorizationId,
        address payer,
        address recipient
    ) private returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidMandate();
        executing = true;
        bytes memory result = poolManager.unlock(
            abi.encode(
                SwapOperation({
                    key: key,
                    params: SwapParams({
                        zeroForOne: zeroForOne,
                        amountSpecified: -int256(uint256(amountIn)),
                        sqrtPriceLimitX96: sqrtPriceLimitX96
                    }),
                    authorizationId: authorizationId,
                    payer: payer,
                    recipient: recipient
                })
            )
        );
        executing = false;
        amountOut = abi.decode(result, (uint256));
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        if (!executing) revert NotExecuting();
        SwapOperation memory operation = abi.decode(data, (SwapOperation));
        BalanceDelta delta = poolManager.swap(
            operation.key,
            operation.params,
            abi.encode(operation.authorizationId)
        );
        _settleOrTake(operation.key.currency0, delta.amount0(), operation.payer, operation.recipient);
        _settleOrTake(operation.key.currency1, delta.amount1(), operation.payer, operation.recipient);

        int128 outputDelta = operation.params.zeroForOne ? delta.amount1() : delta.amount0();
        if (outputDelta <= 0) revert InsufficientOutput();
        return abi.encode(uint256(uint128(outputDelta)));
    }

    function _settleOrTake(Currency currency, int128 delta, address payer, address recipient) private {
        if (delta < 0) {
            uint256 amount = uint256(-int256(delta));
            poolManager.sync(currency);
            if (!IERC20(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount)) {
                revert TokenTransferFailed();
            }
            poolManager.settle();
        } else if (delta > 0) {
            poolManager.take(currency, recipient, uint256(uint128(delta)));
        }
    }

    function _validatePool(PoolKey memory key) private view {
        if (
            hook == address(0) || address(key.hooks) != hook || PoolId.unwrap(key.toId()) != configuredPoolId
        ) revert InvalidConfiguration();
        if (Currency.unwrap(key.currency0) == address(0) || Currency.unwrap(key.currency1) == address(0)) {
            revert NativeCurrencyUnsupported();
        }
    }

    function _recover(bytes32 digest, bytes calldata signature) private pure returns (address signer) {
        if (signature.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert InvalidSignature();
        if (uint256(s) > SECP256K1N_DIV_2) revert InvalidSignature();
        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }
}
