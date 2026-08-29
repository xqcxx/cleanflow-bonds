// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CleanFlowTypes} from "./CleanFlowTypes.sol";
import {ExecutorBondVault} from "./ExecutorBondVault.sol";
import {LpCompensationVault} from "./LpCompensationVault.sol";
import {IERC20, TokenUtils} from "./TokenUtils.sol";

contract CleanFlowController {
    using TokenUtils for IERC20;

    uint16 public constant BPS = 10_000;
    uint16 public constant TRADER_SHARE_BPS = 6_000;
    uint16 public constant LP_SHARE_BPS = 3_000;

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidAuthorization();
    error InvalidWarrantyState();
    error ResolutionNotReady();
    error CallbackReplay();
    error NothingToClaim();

    IERC20 public immutable bondToken;
    ExecutorBondVault public immutable bondVault;
    LpCompensationVault public immutable lpVault;
    address public immutable callbackProxy;
    address public immutable safetyReserve;
    address public immutable owner;
    uint128 public immutable reservationAmount;
    uint64 public immutable resolutionDelayBlocks;

    address public router;
    address public hook;
    address public expectedRvmId;
    uint256 public nextAuthorizationNonce;
    uint64 public nextSequence;

    mapping(bytes32 executionId => CleanFlowTypes.Warranty) public warranties;
    mapping(bytes32 authorizationId => CleanFlowTypes.Authorization) public authorizations;
    mapping(uint64 callbackNonce => bool) public callbackNonceUsed;
    mapping(address trader => uint256) public traderClaimable;

    event RouterSet(address indexed router);
    event HookSet(address indexed hook);
    event ExpectedRvmIdSet(address indexed rvmId);
    event WarrantyOpened(
        bytes32 indexed executionId,
        address indexed trader,
        address indexed executor,
        uint256 reservedBond,
        uint64 snapshotBlock,
        uint64 resolutionBlock
    );
    event AuthorizationCreated(
        bytes32 indexed authorizationId,
        CleanFlowTypes.AuthorizationKind indexed kind,
        address indexed executor,
        bytes32 executionId
    );
    event SwapRecorded(bytes32 indexed authorizationId, uint64 indexed sequence, uint256 amountIn, uint256 amountOut);
    event ViolationOpened(bytes32 indexed executionId, bytes32 indexed evidenceHash, uint64 callbackNonce);
    event WarrantyResolutionRequested(bytes32 indexed executionId);
    event WarrantyCleared(bytes32 indexed executionId, uint256 releasedBond, uint64 callbackNonce);
    event WarrantySlashed(
        bytes32 indexed executionId,
        uint256 slashAmount,
        uint256 traderAmount,
        uint256 lpAmount,
        uint256 reserveAmount,
        uint64 callbackNonce
    );
    event TraderCompensationClaimed(address indexed trader, uint256 amount);

    modifier onlyRouter() {
        if (msg.sender != router) revert Unauthorized();
        _;
    }

    modifier onlyHook() {
        if (msg.sender != hook) revert Unauthorized();
        _;
    }

    constructor(
        IERC20 bondToken_,
        ExecutorBondVault bondVault_,
        LpCompensationVault lpVault_,
        address callbackProxy_,
        address safetyReserve_,
        uint128 reservationAmount_,
        uint64 resolutionDelayBlocks_
    ) {
        if (
            address(bondToken_) == address(0) || address(bondVault_) == address(0)
                || address(lpVault_) == address(0) || callbackProxy_ == address(0) || safetyReserve_ == address(0)
                || reservationAmount_ == 0 || resolutionDelayBlocks_ == 0
        ) revert InvalidConfiguration();
        bondToken = bondToken_;
        bondVault = bondVault_;
        lpVault = lpVault_;
        callbackProxy = callbackProxy_;
        safetyReserve = safetyReserve_;
        reservationAmount = reservationAmount_;
        resolutionDelayBlocks = resolutionDelayBlocks_;
        owner = msg.sender;
    }

    function setRouter(address router_) external {
        if (msg.sender != owner || router != address(0) || router_ == address(0)) revert Unauthorized();
        router = router_;
        emit RouterSet(router_);
    }

    function setHook(address hook_) external {
        if (msg.sender != owner || hook != address(0) || hook_ == address(0)) revert Unauthorized();
        hook = hook_;
        emit HookSet(hook_);
    }

    function setExpectedRvmId(address rvmId) external {
        if (msg.sender != owner || expectedRvmId != address(0) || rvmId == address(0)) revert Unauthorized();
        expectedRvmId = rvmId;
        emit ExpectedRvmIdSet(rvmId);
    }

    function beginProtectedExecution(
        bytes32 executionId,
        address trader,
        address executor,
        bytes32 poolId,
        bool zeroForOne,
        uint128 amountIn
    ) external onlyRouter returns (bytes32 authorizationId) {
        if (
            executionId == bytes32(0) || trader == address(0) || executor == address(0)
                || warranties[executionId].state != CleanFlowTypes.WarrantyState.None || block.number == 0
        ) revert InvalidAuthorization();

        uint64 snapshotBlock = uint64(block.number - 1);
        if (lpVault.totalSupplyAt(snapshotBlock) == 0) revert InvalidConfiguration();
        bondVault.reserve(executionId, executor, reservationAmount);
        warranties[executionId] = CleanFlowTypes.Warranty({
            trader: trader,
            executor: executor,
            reservedBond: reservationAmount,
            openedAtBlock: uint64(block.number),
            resolutionBlock: uint64(block.number) + resolutionDelayBlocks,
            snapshotBlock: snapshotBlock,
            sequence: 0,
            evidenceHash: bytes32(0),
            state: CleanFlowTypes.WarrantyState.Pending
        });
        authorizationId = _createAuthorization(
            CleanFlowTypes.AuthorizationKind.Protected,
            executionId,
            trader,
            executor,
            poolId,
            zeroForOne,
            amountIn
        );
        emit WarrantyOpened(
            executionId,
            trader,
            executor,
            reservationAmount,
            snapshotBlock,
            uint64(block.number) + resolutionDelayBlocks
        );
    }

    function authorizeInventoryTrade(
        address executor,
        bytes32 poolId,
        bool zeroForOne,
        uint128 amountIn
    ) external onlyRouter returns (bytes32 authorizationId) {
        if (!bondVault.isRegistered(executor)) revert InvalidAuthorization();
        bytes32 tradeId = keccak256(abi.encode(executor, poolId, ++nextAuthorizationNonce, block.chainid));
        authorizationId = _createAuthorization(
            CleanFlowTypes.AuthorizationKind.Inventory,
            tradeId,
            address(0),
            executor,
            poolId,
            zeroForOne,
            amountIn
        );
    }

    function consumeAuthorization(bytes32 authorizationId, bytes32 poolId, bool zeroForOne, uint256 amountIn)
        external
        onlyHook
        returns (CleanFlowTypes.AuthorizationKind kind)
    {
        CleanFlowTypes.Authorization storage authorization = authorizations[authorizationId];
        if (
            authorization.kind == CleanFlowTypes.AuthorizationKind.None || authorization.consumed
                || authorization.poolId != poolId || authorization.zeroForOne != zeroForOne
                || authorization.amountIn != amountIn
        ) revert InvalidAuthorization();
        authorization.consumed = true;
        return authorization.kind;
    }

    function recordSwap(bytes32 authorizationId, uint256 amountIn, uint256 amountOut)
        external
        onlyHook
        returns (uint64 sequence, CleanFlowTypes.Authorization memory authorization)
    {
        CleanFlowTypes.Authorization storage stored = authorizations[authorizationId];
        if (!stored.consumed || stored.recorded || amountIn == 0 || amountOut == 0) revert InvalidAuthorization();
        stored.recorded = true;
        sequence = ++nextSequence;
        if (stored.kind == CleanFlowTypes.AuthorizationKind.Protected) {
            warranties[stored.executionId].sequence = sequence;
        }
        authorization = stored;
        emit SwapRecorded(authorizationId, sequence, amountIn, amountOut);
    }

    function requestWarrantyResolution(bytes32 executionId) external {
        CleanFlowTypes.Warranty storage warranty = warranties[executionId];
        if (
            warranty.state != CleanFlowTypes.WarrantyState.Pending
                && warranty.state != CleanFlowTypes.WarrantyState.Challenged
        ) revert InvalidWarrantyState();
        if (block.number < warranty.resolutionBlock) revert ResolutionNotReady();
        emit WarrantyResolutionRequested(executionId);
    }

    function openViolation(address rvmId, bytes32 executionId, bytes32 evidenceHash, uint64 callbackNonce) external {
        _authenticateCallback(rvmId, callbackNonce);
        CleanFlowTypes.Warranty storage warranty = warranties[executionId];
        if (warranty.state != CleanFlowTypes.WarrantyState.Pending || evidenceHash == bytes32(0)) {
            revert InvalidWarrantyState();
        }
        warranty.state = CleanFlowTypes.WarrantyState.Challenged;
        warranty.evidenceHash = evidenceHash;
        emit ViolationOpened(executionId, evidenceHash, callbackNonce);
    }

    function clearExecution(address rvmId, bytes32 executionId, uint64 callbackNonce) external {
        _authenticateCallback(rvmId, callbackNonce);
        CleanFlowTypes.Warranty storage warranty = warranties[executionId];
        if (warranty.state != CleanFlowTypes.WarrantyState.Pending) revert InvalidWarrantyState();
        if (block.number < warranty.resolutionBlock) revert ResolutionNotReady();
        warranty.state = CleanFlowTypes.WarrantyState.Cleared;
        uint128 released = bondVault.release(executionId);
        emit WarrantyCleared(executionId, released, callbackNonce);
    }

    function finalizeViolation(address rvmId, bytes32 executionId, uint64 callbackNonce) external {
        _authenticateCallback(rvmId, callbackNonce);
        CleanFlowTypes.Warranty storage warranty = warranties[executionId];
        if (warranty.state != CleanFlowTypes.WarrantyState.Challenged) revert InvalidWarrantyState();
        if (block.number < warranty.resolutionBlock) revert ResolutionNotReady();
        warranty.state = CleanFlowTypes.WarrantyState.Slashed;

        uint256 slashAmount = bondVault.slash(executionId, address(this));
        uint256 traderAmount = slashAmount * TRADER_SHARE_BPS / BPS;
        uint256 lpAmount = slashAmount * LP_SHARE_BPS / BPS;
        uint256 reserveAmount = slashAmount - traderAmount - lpAmount;
        traderClaimable[warranty.trader] += traderAmount;

        uint256 snapshotSupply = lpVault.totalSupplyAt(warranty.snapshotBlock);
        bondToken.safeTransfer(address(lpVault), lpAmount);
        lpVault.allocateReward(executionId, lpAmount, warranty.snapshotBlock, snapshotSupply);
        bondToken.safeTransfer(safetyReserve, reserveAmount);
        emit WarrantySlashed(
            executionId,
            slashAmount,
            traderAmount,
            lpAmount,
            reserveAmount,
            callbackNonce
        );
    }

    function claimTraderCompensation() external returns (uint256 amount) {
        amount = traderClaimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        traderClaimable[msg.sender] = 0;
        bondToken.safeTransfer(msg.sender, amount);
        emit TraderCompensationClaimed(msg.sender, amount);
    }

    function getWarranty(bytes32 executionId) external view returns (CleanFlowTypes.Warranty memory) {
        return warranties[executionId];
    }

    function getAuthorization(bytes32 authorizationId)
        external
        view
        returns (CleanFlowTypes.Authorization memory)
    {
        return authorizations[authorizationId];
    }

    function _createAuthorization(
        CleanFlowTypes.AuthorizationKind kind,
        bytes32 executionId,
        address trader,
        address executor,
        bytes32 poolId,
        bool zeroForOne,
        uint128 amountIn
    ) private returns (bytes32 authorizationId) {
        if (executor == address(0) || poolId == bytes32(0) || amountIn == 0) revert InvalidAuthorization();
        authorizationId = keccak256(
            abi.encode(address(this), kind, executionId, executor, ++nextAuthorizationNonce, block.chainid)
        );
        authorizations[authorizationId] = CleanFlowTypes.Authorization({
            kind: kind,
            executor: executor,
            trader: trader,
            executionId: executionId,
            poolId: poolId,
            amountIn: amountIn,
            zeroForOne: zeroForOne,
            consumed: false,
            recorded: false
        });
        emit AuthorizationCreated(authorizationId, kind, executor, executionId);
    }

    function _authenticateCallback(address rvmId, uint64 callbackNonce) private {
        if (msg.sender != callbackProxy || rvmId == address(0) || rvmId != expectedRvmId) revert Unauthorized();
        if (callbackNonceUsed[callbackNonce]) revert CallbackReplay();
        callbackNonceUsed[callbackNonce] = true;
    }
}
