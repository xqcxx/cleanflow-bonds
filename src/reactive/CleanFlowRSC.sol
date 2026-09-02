// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReactive} from "reactive-lib/interfaces/IReactive.sol";
import {AbstractReactive} from "reactive-lib/abstract-base/AbstractReactive.sol";

contract CleanFlowRSC is AbstractReactive {
    bytes32 public constant PROTECTED_SWAP_EXECUTED = keccak256(
        "ProtectedSwapExecuted(uint256,bytes32,address,address,bytes32,bool,uint256,uint256,int24,int24,uint64)"
    );
    bytes32 public constant EXECUTOR_TRADE_OBSERVED =
        keccak256("ExecutorTradeObserved(uint256,bytes32,address,bytes32,bool,uint256,uint256)");
    bytes32 public constant WARRANTY_RESOLUTION_REQUESTED =
        keccak256("WarrantyResolutionRequested(bytes32)");
    uint16 public constant BPS = 10_000;
    uint16 public constant AMOUNT_TOLERANCE_BPS = 500;
    uint64 public constant SEQUENCE_WINDOW = 5;

    struct Trade {
        uint64 sequence;
        bytes32 tradeId;
        bytes32 eventId;
        bool zeroForOne;
        uint256 amountIn;
        uint256 amountOut;
        bool exists;
    }

    struct Candidate {
        bytes32 executionId;
        bytes32 poolId;
        address executor;
        uint64 protectedSequence;
        bytes32 protectedEventId;
        Trade front;
        bool zeroForOne;
        bool active;
    }

    uint256 public immutable originChainId;
    uint256 public immutable destinationChainId;
    address public immutable originHook;
    address public immutable originController;
    address public immutable destinationController;
    uint64 public immutable callbackGasLimit;
    uint256 public immutable profitThreshold;
    uint64 public nextCallbackNonce;

    mapping(bytes32 eventId => bool) public processedLog;
    mapping(bytes32 executorPoolKey => Trade) public latestTrade;
    mapping(bytes32 executionId => Candidate) private candidates;
    mapping(bytes32 executorPoolKey => bytes32 executionId) public activeExecution;
    mapping(bytes32 executionId => bytes32 evidenceHash) public evidence;

    event ViolationCallbackRequested(
        bytes32 indexed executionId,
        bytes32 indexed evidenceHash,
        uint64 indexed callbackNonce
    );
    event ResolutionCallbackRequested(
        bytes32 indexed executionId,
        bool indexed violated,
        uint64 indexed callbackNonce
    );

    constructor(
        uint256 originChainId_,
        uint256 destinationChainId_,
        address originHook_,
        address originController_,
        address destinationController_,
        uint64 callbackGasLimit_,
        uint256 profitThreshold_
    ) payable {
        require(
            originHook_ != address(0) && originController_ != address(0)
                && destinationController_ != address(0) && profitThreshold_ != 0,
            "invalid configuration"
        );
        originChainId = originChainId_;
        destinationChainId = destinationChainId_;
        originHook = originHook_;
        originController = originController_;
        destinationController = destinationController_;
        callbackGasLimit = callbackGasLimit_;
        profitThreshold = profitThreshold_;

        if (!vm) {
            service.subscribe(
                originChainId_,
                originHook_,
                uint256(PROTECTED_SWAP_EXECUTED),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            service.subscribe(
                originChainId_,
                originHook_,
                uint256(EXECUTOR_TRADE_OBSERVED),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            service.subscribe(
                originChainId_,
                originController_,
                uint256(WARRANTY_RESOLUTION_REQUESTED),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(IReactive.LogRecord calldata log) external override vmOnly {
        if (log.chain_id != originChainId) return;
        bool hookEvent = log._contract == originHook
            && (log.topic_0 == uint256(PROTECTED_SWAP_EXECUTED) || log.topic_0 == uint256(EXECUTOR_TRADE_OBSERVED));
        bool resolutionEvent = log._contract == originController
            && log.topic_0 == uint256(WARRANTY_RESOLUTION_REQUESTED);
        if (!hookEvent && !resolutionEvent) return;

        bytes32 eventId = keccak256(abi.encode(log.chain_id, log.tx_hash, log.log_index));
        if (processedLog[eventId]) return;
        processedLog[eventId] = true;

        if (log.topic_0 == uint256(EXECUTOR_TRADE_OBSERVED)) {
            _observeTrade(log, eventId);
        } else if (log.topic_0 == uint256(PROTECTED_SWAP_EXECUTED)) {
            _observeProtected(log, eventId);
        } else {
            _resolve(bytes32(log.topic_1));
        }
    }

    function getCandidate(bytes32 executionId) external view returns (Candidate memory) {
        return candidates[executionId];
    }

    function _observeTrade(IReactive.LogRecord calldata log, bytes32 eventId) private {
        uint64 sequence = uint64(log.topic_1);
        bytes32 tradeId = bytes32(log.topic_2);
        address executor = address(uint160(log.topic_3));
        (bytes32 poolId, bool zeroForOne, uint256 amountIn, uint256 amountOut) =
            abi.decode(log.data, (bytes32, bool, uint256, uint256));
        bytes32 key = keccak256(abi.encode(executor, poolId));
        bytes32 executionId = activeExecution[key];
        Candidate storage candidate = candidates[executionId];

        if (
            executionId != bytes32(0) && candidate.active && sequence > candidate.protectedSequence
                && sequence - candidate.protectedSequence <= SEQUENCE_WINDOW && zeroForOne != candidate.zeroForOne
                && _withinTolerance(amountIn, candidate.front.amountOut)
                && amountOut >= candidate.front.amountIn + profitThreshold
        ) {
            bytes32 evidenceHash = keccak256(
                abi.encode(
                    candidate.front.eventId,
                    candidate.protectedEventId,
                    eventId,
                    candidate.front.tradeId,
                    executionId,
                    tradeId
                )
            );
            evidence[executionId] = evidenceHash;
            candidate.active = false;
            delete activeExecution[key];
            uint64 callbackNonce = ++nextCallbackNonce;
            bytes memory payload = abi.encodeWithSignature(
                "openViolation(address,bytes32,bytes32,uint64)",
                address(0),
                executionId,
                evidenceHash,
                callbackNonce
            );
            emit Callback(destinationChainId, destinationController, callbackGasLimit, payload);
            emit ViolationCallbackRequested(executionId, evidenceHash, callbackNonce);
            return;
        }

        latestTrade[key] = Trade({
            sequence: sequence,
            tradeId: tradeId,
            eventId: eventId,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            amountOut: amountOut,
            exists: true
        });
    }

    function _observeProtected(IReactive.LogRecord calldata log, bytes32 eventId) private {
        uint64 sequence = uint64(log.topic_1);
        bytes32 executionId = bytes32(log.topic_2);
        address executor = address(uint160(log.topic_3));
        (, bytes32 poolId, bool zeroForOne,,,,,) =
            abi.decode(log.data, (address, bytes32, bool, uint256, uint256, int24, int24, uint64));
        bytes32 key = keccak256(abi.encode(executor, poolId));
        Trade memory front = latestTrade[key];
        if (
            !front.exists || front.zeroForOne != zeroForOne || sequence <= front.sequence
                || sequence - front.sequence > SEQUENCE_WINDOW
        ) return;

        candidates[executionId] = Candidate({
            executionId: executionId,
            poolId: poolId,
            executor: executor,
            protectedSequence: sequence,
            protectedEventId: eventId,
            front: front,
            zeroForOne: zeroForOne,
            active: true
        });
        activeExecution[key] = executionId;
    }

    function _resolve(bytes32 executionId) private {
        bool violated = evidence[executionId] != bytes32(0);
        uint64 callbackNonce = ++nextCallbackNonce;
        bytes memory payload = violated
            ? abi.encodeWithSignature(
                "finalizeViolation(address,bytes32,uint64)",
                address(0),
                executionId,
                callbackNonce
            )
            : abi.encodeWithSignature(
                "clearExecution(address,bytes32,uint64)",
                address(0),
                executionId,
                callbackNonce
            );
        emit Callback(destinationChainId, destinationController, callbackGasLimit, payload);
        emit ResolutionCallbackRequested(executionId, violated, callbackNonce);
    }

    function _withinTolerance(uint256 actual, uint256 expected) private pure returns (bool) {
        uint256 difference = actual > expected ? actual - expected : expected - actual;
        return difference <= expected * AMOUNT_TOLERANCE_BPS / BPS;
    }
}
