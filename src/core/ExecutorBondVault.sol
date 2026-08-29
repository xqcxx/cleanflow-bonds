// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20, TokenUtils} from "./TokenUtils.sol";

contract ExecutorBondVault {
    using TokenUtils for IERC20;

    error Unauthorized();
    error InvalidAmount();
    error InsufficientAvailableBond();
    error ReservationExists();
    error InvalidReservation();
    error WithdrawalNotReady();

    struct Account {
        uint128 available;
        uint128 reserved;
        uint128 withdrawalAmount;
        uint64 withdrawalAvailableAt;
        bool registered;
    }

    struct Reservation {
        address executor;
        uint128 amount;
        bool active;
    }

    IERC20 public immutable bondToken;
    address public immutable owner;
    uint64 public immutable withdrawalDelay;
    address public controller;
    uint256 public totalAvailable;
    uint256 public totalReserved;

    mapping(address executor => Account) public accounts;
    mapping(bytes32 executionId => Reservation) public reservations;

    event ControllerSet(address indexed controller);
    event BondDeposited(address indexed executor, uint256 amount);
    event BondReserved(bytes32 indexed executionId, address indexed executor, uint256 amount);
    event BondReleased(bytes32 indexed executionId, address indexed executor, uint256 amount);
    event BondSlashed(bytes32 indexed executionId, address indexed executor, uint256 amount, address recipient);
    event WithdrawalRequested(address indexed executor, uint256 amount, uint64 availableAt);
    event BondWithdrawn(address indexed executor, uint256 amount);

    modifier onlyController() {
        if (msg.sender != controller) revert Unauthorized();
        _;
    }

    constructor(IERC20 bondToken_, uint64 withdrawalDelay_) {
        if (address(bondToken_) == address(0)) revert Unauthorized();
        bondToken = bondToken_;
        withdrawalDelay = withdrawalDelay_;
        owner = msg.sender;
    }

    function setController(address controller_) external {
        if (msg.sender != owner || controller != address(0) || controller_ == address(0)) revert Unauthorized();
        controller = controller_;
        emit ControllerSet(controller_);
    }

    function deposit(uint128 amount) external {
        if (amount == 0) revert InvalidAmount();
        bondToken.safeTransferFrom(msg.sender, address(this), amount);
        Account storage account = accounts[msg.sender];
        account.registered = true;
        account.available += amount;
        totalAvailable += amount;
        emit BondDeposited(msg.sender, amount);
    }

    function reserve(bytes32 executionId, address executor, uint128 amount) external onlyController {
        Account storage account = accounts[executor];
        if (amount == 0) revert InvalidAmount();
        if (reservations[executionId].active) revert ReservationExists();
        if (!account.registered || account.available < amount) revert InsufficientAvailableBond();
        account.available -= amount;
        account.reserved += amount;
        totalAvailable -= amount;
        totalReserved += amount;
        reservations[executionId] = Reservation({executor: executor, amount: amount, active: true});
        emit BondReserved(executionId, executor, amount);
    }

    function release(bytes32 executionId) external onlyController returns (uint128 amount) {
        Reservation storage reservation = reservations[executionId];
        if (!reservation.active) revert InvalidReservation();
        reservation.active = false;
        amount = reservation.amount;
        Account storage account = accounts[reservation.executor];
        account.reserved -= amount;
        account.available += amount;
        totalReserved -= amount;
        totalAvailable += amount;
        emit BondReleased(executionId, reservation.executor, amount);
    }

    function slash(bytes32 executionId, address recipient) external onlyController returns (uint128 amount) {
        Reservation storage reservation = reservations[executionId];
        if (!reservation.active || recipient == address(0)) revert InvalidReservation();
        reservation.active = false;
        amount = reservation.amount;
        accounts[reservation.executor].reserved -= amount;
        totalReserved -= amount;
        bondToken.safeTransfer(recipient, amount);
        emit BondSlashed(executionId, reservation.executor, amount, recipient);
    }

    function requestWithdrawal(uint128 amount) external {
        Account storage account = accounts[msg.sender];
        if (amount == 0 || account.available < amount) revert InvalidAmount();
        uint64 availableAt = uint64(block.timestamp) + withdrawalDelay;
        account.withdrawalAmount = amount;
        account.withdrawalAvailableAt = availableAt;
        emit WithdrawalRequested(msg.sender, amount, availableAt);
    }

    function isRegistered(address executor) external view returns (bool) {
        return accounts[executor].registered;
    }

    function withdraw() external returns (uint128 amount) {
        Account storage account = accounts[msg.sender];
        amount = account.withdrawalAmount;
        if (amount == 0 || block.timestamp < account.withdrawalAvailableAt) revert WithdrawalNotReady();
        if (account.available < amount) revert InsufficientAvailableBond();
        account.withdrawalAmount = 0;
        account.withdrawalAvailableAt = 0;
        account.available -= amount;
        totalAvailable -= amount;
        bondToken.safeTransfer(msg.sender, amount);
        emit BondWithdrawn(msg.sender, amount);
    }
}
