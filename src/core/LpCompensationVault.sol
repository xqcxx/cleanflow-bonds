// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20, TokenUtils} from "./TokenUtils.sol";

contract LpCompensationVault {
    using TokenUtils for IERC20;

    uint256 private constant INDEX_SCALE = 1e18;

    error Unauthorized();
    error InvalidAmount();
    error ValueTooLarge();
    error AlreadyAllocated();
    error AlreadyClaimed();

    struct Checkpoint {
        uint64 fromBlock;
        uint192 value;
    }

    struct Reward {
        uint256 index;
        uint256 amount;
        uint64 snapshotBlock;
        bool allocated;
    }

    IERC20 public immutable liquidityToken;
    IERC20 public immutable rewardToken;
    address public immutable owner;
    address public controller;
    uint256 public totalSupply;
    uint256 public totalAllocated;
    uint256 public totalClaimed;

    mapping(address lp => uint256) public balanceOf;
    mapping(address lp => Checkpoint[]) private accountCheckpoints;
    Checkpoint[] private supplyCheckpoints;
    mapping(bytes32 executionId => Reward) public rewards;
    mapping(bytes32 executionId => mapping(address lp => bool)) public claimed;

    event ControllerSet(address indexed controller);
    event Deposited(address indexed lp, uint256 shares);
    event Withdrawn(address indexed lp, uint256 shares);
    event RewardAllocated(bytes32 indexed executionId, uint256 amount, uint64 snapshotBlock, uint256 snapshotSupply);
    event RewardClaimed(bytes32 indexed executionId, address indexed lp, uint256 amount);

    modifier onlyController() {
        if (msg.sender != controller) revert Unauthorized();
        _;
    }

    constructor(IERC20 liquidityToken_, IERC20 rewardToken_) {
        if (address(liquidityToken_) == address(0) || address(rewardToken_) == address(0)) revert Unauthorized();
        liquidityToken = liquidityToken_;
        rewardToken = rewardToken_;
        owner = msg.sender;
    }

    function setController(address controller_) external {
        if (msg.sender != owner || controller != address(0) || controller_ == address(0)) revert Unauthorized();
        controller = controller_;
        emit ControllerSet(controller_);
    }

    function deposit(uint256 shares) external {
        if (shares == 0) revert InvalidAmount();
        liquidityToken.safeTransferFrom(msg.sender, address(this), shares);
        balanceOf[msg.sender] += shares;
        totalSupply += shares;
        _write(accountCheckpoints[msg.sender], balanceOf[msg.sender]);
        _write(supplyCheckpoints, totalSupply);
        emit Deposited(msg.sender, shares);
    }

    function withdraw(uint256 shares) external {
        if (shares == 0 || balanceOf[msg.sender] < shares) revert InvalidAmount();
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        _write(accountCheckpoints[msg.sender], balanceOf[msg.sender]);
        _write(supplyCheckpoints, totalSupply);
        liquidityToken.safeTransfer(msg.sender, shares);
        emit Withdrawn(msg.sender, shares);
    }

    function totalSupplyAt(uint64 blockNumber) public view returns (uint256) {
        return _lookup(supplyCheckpoints, blockNumber);
    }

    function balanceOfAt(address account, uint64 blockNumber) public view returns (uint256) {
        return _lookup(accountCheckpoints[account], blockNumber);
    }

    function allocateReward(bytes32 executionId, uint256 amount, uint64 snapshotBlock, uint256 snapshotSupply)
        external
        onlyController
    {
        if (rewards[executionId].allocated || amount == 0 || snapshotSupply == 0) revert AlreadyAllocated();
        rewards[executionId] = Reward({
            index: amount * INDEX_SCALE / snapshotSupply,
            amount: amount,
            snapshotBlock: snapshotBlock,
            allocated: true
        });
        totalAllocated += amount;
        emit RewardAllocated(executionId, amount, snapshotBlock, snapshotSupply);
    }

    function claim(bytes32 executionId) external returns (uint256 amount) {
        Reward memory reward = rewards[executionId];
        if (!reward.allocated || claimed[executionId][msg.sender]) revert AlreadyClaimed();
        claimed[executionId][msg.sender] = true;
        amount = balanceOfAt(msg.sender, reward.snapshotBlock) * reward.index / INDEX_SCALE;
        totalClaimed += amount;
        if (amount != 0) rewardToken.safeTransfer(msg.sender, amount);
        emit RewardClaimed(executionId, msg.sender, amount);
    }

    function _write(Checkpoint[] storage checkpoints, uint256 value) private {
        if (value > type(uint192).max) revert ValueTooLarge();
        uint64 currentBlock = uint64(block.number);
        uint256 length = checkpoints.length;
        if (length != 0 && checkpoints[length - 1].fromBlock == currentBlock) {
            checkpoints[length - 1].value = uint192(value);
        } else {
            checkpoints.push(Checkpoint({fromBlock: currentBlock, value: uint192(value)}));
        }
    }

    function _lookup(Checkpoint[] storage checkpoints, uint64 blockNumber) private view returns (uint256) {
        uint256 length = checkpoints.length;
        if (length == 0 || checkpoints[0].fromBlock > blockNumber) return 0;
        uint256 low;
        uint256 high = length;
        while (low < high) {
            uint256 middle = (low + high) / 2;
            if (checkpoints[middle].fromBlock <= blockNumber) low = middle + 1;
            else high = middle;
        }
        return checkpoints[low - 1].value;
    }
}
