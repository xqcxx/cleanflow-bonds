// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CleanFlowTypes} from "../../src/core/CleanFlowTypes.sol";
import {ExecutorBondVault} from "../../src/core/ExecutorBondVault.sol";
import {LpCompensationVault} from "../../src/core/LpCompensationVault.sol";
import {CleanFlowController} from "../../src/core/CleanFlowController.sol";
import {IERC20} from "../../src/core/TokenUtils.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract CleanFlowCoreTest is Test {
    uint128 internal constant RESERVATION = 100e6;
    address internal constant ROUTER = address(0x1001);
    address internal constant HOOK = address(0x1002);
    address internal constant CALLBACK_PROXY = address(0x1003);
    address internal constant RVM_ID = address(0x1004);
    address internal constant SAFETY_RESERVE = address(0x1005);
    address internal constant EXECUTOR = address(0x2001);
    address internal constant TRADER = address(0x2002);
    address internal constant ALICE = address(0x2003);
    address internal constant BAO = address(0x2004);
    address internal constant LATE_LP = address(0x2005);
    bytes32 internal constant POOL_ID = keccak256("CLEANFLOW_POOL");

    MockERC20 internal bondToken;
    MockERC20 internal lpToken;
    ExecutorBondVault internal bondVault;
    LpCompensationVault internal lpVault;
    CleanFlowController internal controller;

    function setUp() public {
        vm.roll(10);
        bondToken = new MockERC20("Demo USDC", "dUSDC", 6);
        lpToken = new MockERC20("CleanFlow LP", "cfLP", 18);
        bondVault = new ExecutorBondVault(IERC20(address(bondToken)), 1 days);
        lpVault = new LpCompensationVault(IERC20(address(lpToken)), IERC20(address(bondToken)));
        controller = new CleanFlowController(
            IERC20(address(bondToken)),
            bondVault,
            lpVault,
            CALLBACK_PROXY,
            SAFETY_RESERVE,
            RESERVATION,
            5
        );
        bondVault.setController(address(controller));
        lpVault.setController(address(controller));
        controller.setRouter(ROUTER);
        controller.setHook(HOOK);
        controller.setExpectedRvmId(RVM_ID);

        bondToken.mint(EXECUTOR, 1_000e6);
        vm.startPrank(EXECUTOR);
        bondToken.approve(address(bondVault), type(uint256).max);
        bondVault.deposit(1_000e6);
        vm.stopPrank();

        lpToken.mint(ALICE, 60e18);
        lpToken.mint(BAO, 40e18);
        vm.startPrank(ALICE);
        lpToken.approve(address(lpVault), type(uint256).max);
        lpVault.deposit(60e18);
        vm.stopPrank();
        vm.startPrank(BAO);
        lpToken.approve(address(lpVault), type(uint256).max);
        lpVault.deposit(40e18);
        vm.stopPrank();
        vm.roll(11);
    }

    function test_CleanExecutionReleasesReservationExactlyOnce() public {
        bytes32 executionId = keccak256("clean");
        bytes32 authorizationId = _openAndRecord(executionId);

        CleanFlowTypes.Authorization memory authorization = controller.getAuthorization(authorizationId);
        assertTrue(authorization.recorded);
        assertEq(uint8(controller.getWarranty(executionId).state), uint8(CleanFlowTypes.WarrantyState.Pending));
        (uint128 available, uint128 reserved,,,) = bondVault.accounts(EXECUTOR);
        assertEq(available, 900e6);
        assertEq(reserved, RESERVATION);

        vm.roll(controller.getWarranty(executionId).resolutionBlock);
        controller.requestWarrantyResolution(executionId);
        vm.prank(CALLBACK_PROXY);
        controller.clearExecution(RVM_ID, executionId, 1);

        (available, reserved,,,) = bondVault.accounts(EXECUTOR);
        assertEq(available, 1_000e6);
        assertEq(reserved, 0);
        assertEq(uint8(controller.getWarranty(executionId).state), uint8(CleanFlowTypes.WarrantyState.Cleared));

        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(CleanFlowController.CallbackReplay.selector);
        controller.clearExecution(RVM_ID, executionId, 1);
    }

    function test_ViolationAllocatesSlashToTraderSnapshotLpsAndReserve() public {
        bytes32 executionId = keccak256("violated");
        _openAndRecord(executionId);
        bytes32 evidenceHash = keccak256("front-protected-back");

        vm.prank(CALLBACK_PROXY);
        controller.openViolation(RVM_ID, executionId, evidenceHash, 1);
        vm.roll(controller.getWarranty(executionId).resolutionBlock);
        controller.requestWarrantyResolution(executionId);
        vm.prank(CALLBACK_PROXY);
        controller.finalizeViolation(RVM_ID, executionId, 2);

        assertEq(controller.traderClaimable(TRADER), 60e6);
        assertEq(bondToken.balanceOf(SAFETY_RESERVE), 10e6);
        assertEq(bondToken.balanceOf(address(lpVault)), 30e6);
        assertEq(uint8(controller.getWarranty(executionId).state), uint8(CleanFlowTypes.WarrantyState.Slashed));

        vm.prank(TRADER);
        controller.claimTraderCompensation();
        vm.prank(ALICE);
        uint256 aliceClaim = lpVault.claim(executionId);
        vm.prank(BAO);
        uint256 baoClaim = lpVault.claim(executionId);
        assertEq(bondToken.balanceOf(TRADER), 60e6);
        assertEq(aliceClaim, 18e6);
        assertEq(baoClaim, 12e6);
        assertEq(bondToken.balanceOf(ALICE), 18e6);
        assertEq(bondToken.balanceOf(BAO), 12e6);
        assertEq(lpVault.totalClaimed(), 30e6);
    }

    function test_LiquidityDepositedInExecutionBlockCannotClaim() public {
        bytes32 executionId = keccak256("late-lp");
        _openAndRecord(executionId);

        lpToken.mint(LATE_LP, 100e18);
        vm.startPrank(LATE_LP);
        lpToken.approve(address(lpVault), type(uint256).max);
        lpVault.deposit(100e18);
        vm.stopPrank();

        vm.prank(CALLBACK_PROXY);
        controller.openViolation(RVM_ID, executionId, keccak256("evidence"), 1);
        vm.roll(controller.getWarranty(executionId).resolutionBlock);
        vm.prank(CALLBACK_PROXY);
        controller.finalizeViolation(RVM_ID, executionId, 2);

        vm.prank(LATE_LP);
        assertEq(lpVault.claim(executionId), 0);
        assertEq(bondToken.balanceOf(LATE_LP), 0);
    }

    function test_RejectsUnauthorizedAndWrongRvmCallbacks() public {
        bytes32 executionId = keccak256("callback-auth");
        _openAndRecord(executionId);

        vm.expectRevert(CleanFlowController.Unauthorized.selector);
        controller.openViolation(RVM_ID, executionId, keccak256("evidence"), 1);

        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(CleanFlowController.Unauthorized.selector);
        controller.openViolation(address(0xBAD), executionId, keccak256("evidence"), 1);
    }

    function test_ReservedCollateralCannotBeWithdrawn() public {
        _openAndRecord(keccak256("reserved"));
        vm.prank(EXECUTOR);
        vm.expectRevert(ExecutorBondVault.InvalidAmount.selector);
        bondVault.requestWithdrawal(1_000e6);
    }

    function testFuzz_ClaimsNeverExceedSlash(uint96 aliceShares, uint96 baoShares) public {
        aliceShares = uint96(bound(aliceShares, 1, 1e30));
        baoShares = uint96(bound(baoShares, 1, 1e30));

        MockERC20 shares = new MockERC20("Fuzz LP", "fLP", 18);
        LpCompensationVault vault = new LpCompensationVault(IERC20(address(shares)), IERC20(address(bondToken)));
        vault.setController(address(this));
        shares.mint(ALICE, aliceShares);
        shares.mint(BAO, baoShares);
        vm.startPrank(ALICE);
        shares.approve(address(vault), type(uint256).max);
        vault.deposit(aliceShares);
        vm.stopPrank();
        vm.startPrank(BAO);
        shares.approve(address(vault), type(uint256).max);
        vault.deposit(baoShares);
        vm.stopPrank();
        vm.roll(block.number + 1);

        bytes32 rewardId = keccak256("fuzz");
        bondToken.mint(address(vault), 30e6);
        vault.allocateReward(
            rewardId,
            30e6,
            uint64(block.number - 1),
            uint256(aliceShares) + uint256(baoShares)
        );
        vm.prank(ALICE);
        uint256 aliceAmount = vault.claim(rewardId);
        vm.prank(BAO);
        uint256 baoAmount = vault.claim(rewardId);
        assertLe(aliceAmount + baoAmount, 30e6);
    }

    function _openAndRecord(bytes32 executionId) private returns (bytes32 authorizationId) {
        vm.prank(ROUTER);
        authorizationId = controller.beginProtectedExecution(
            executionId,
            TRADER,
            EXECUTOR,
            POOL_ID,
            true,
            10e18
        );
        vm.prank(HOOK);
        controller.consumeAuthorization(authorizationId, POOL_ID, true, 10e18);
        vm.prank(HOOK);
        controller.recordSwap(authorizationId, 10e18, 9e18);
    }
}
