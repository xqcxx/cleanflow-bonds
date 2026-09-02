// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {IReactive} from "reactive-lib/interfaces/IReactive.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {CleanFlowTypes} from "../../src/core/CleanFlowTypes.sol";
import {CleanFlowV4Test} from "./CleanFlowV4.t.sol";

contract CleanFlowLifecycleTest is CleanFlowV4Test {
    function test_CompleteRealV4ReactiveSlashAndClaims() public {
        vm.recordLogs();
        vm.prank(executor);
        (, uint256 frontOutput) = router.executeExecutorTrade(
            key,
            true,
            1e18,
            TickMath.MIN_SQRT_PRICE + 1
        );
        console2.log("01 FRONT TRADE RECEIPT / output", frontOutput);
        _react(vm.getRecordedLogs(), 1);

        CleanFlowTypes.ExecutionMandate memory mandate = _mandate(101, 10e18);
        bytes memory signature = _signMandate(mandate);
        vm.recordLogs();
        vm.prank(executor);
        (bytes32 executionId,) = router.executeProtected(key, mandate, signature);
        console2.log("02 PROTECTED SWAP / fee bps", uint256(5));
        _react(vm.getRecordedLogs(), 2);

        vm.recordLogs();
        vm.prank(executor);
        router.executeExecutorTrade(
            key,
            false,
            uint128(frontOutput),
            TickMath.MAX_SQRT_PRICE - 1
        );
        console2.log("03 PROFITABLE BACK TRADE RECEIPT");
        _react(vm.getRecordedLogs(), 3);

        bytes32 evidenceHash = rsc.evidence(executionId);
        console2.log("04 REACTIVE EVIDENCE HASH");
        console2.logBytes32(evidenceHash);
        assertNotEq(evidenceHash, bytes32(0));
        assertEq(rsc.nextCallbackNonce(), 1);
        vm.prank(CALLBACK_PROXY);
        controller.openViolation(address(rsc), executionId, evidenceHash, 1);
        assertEq(
            uint8(controller.getWarranty(executionId).state),
            uint8(CleanFlowTypes.WarrantyState.Challenged)
        );

        vm.roll(controller.getWarranty(executionId).resolutionBlock);
        vm.recordLogs();
        controller.requestWarrantyResolution(executionId);
        _react(vm.getRecordedLogs(), 4);
        assertEq(rsc.nextCallbackNonce(), 2);
        vm.prank(CALLBACK_PROXY);
        controller.finalizeViolation(address(rsc), executionId, 2);

        console2.log("05 AUTHENTICATED CALLBACK / warranty state", uint256(uint8(controller.getWarranty(executionId).state)));
        console2.log("06 TRADER ALLOCATION / demo USDC", controller.traderClaimable(trader) / 1e6);
        console2.log("07 LP ALLOCATION / demo USDC", uint256(30));
        console2.log("08 RESERVE ALLOCATION / demo USDC", bondToken.balanceOf(SAFETY_RESERVE) / 1e6);

        assertEq(
            uint8(controller.getWarranty(executionId).state),
            uint8(CleanFlowTypes.WarrantyState.Slashed)
        );
        assertEq(controller.traderClaimable(trader), 60e6);
        assertEq(bondToken.balanceOf(SAFETY_RESERVE), 10e6);
        vm.prank(trader);
        controller.claimTraderCompensation();
        vm.prank(ALICE);
        uint256 lpClaim = lpVault.claim(executionId);
        assertEq(bondToken.balanceOf(trader), 60e6);
        assertEq(lpClaim, 30e6);
    }

    function test_CompleteReactiveCleanBranchReleasesReservation() public {
        CleanFlowTypes.ExecutionMandate memory mandate = _mandate(202, 10e18);
        bytes memory signature = _signMandate(mandate);
        vm.recordLogs();
        vm.prank(executor);
        (bytes32 executionId,) = router.executeProtected(key, mandate, signature);
        _react(vm.getRecordedLogs(), 10);

        vm.roll(controller.getWarranty(executionId).resolutionBlock);
        vm.recordLogs();
        controller.requestWarrantyResolution(executionId);
        Vm.Log[] memory resolutionLogs = vm.getRecordedLogs();
        _react(resolutionLogs, 11);
        assertEq(rsc.nextCallbackNonce(), 1);
        assertEq(rsc.evidence(executionId), bytes32(0));

        vm.prank(CALLBACK_PROXY);
        controller.clearExecution(address(rsc), executionId, 1);
        assertEq(
            uint8(controller.getWarranty(executionId).state),
            uint8(CleanFlowTypes.WarrantyState.Cleared)
        );
        (uint128 available, uint128 reserved,,,) = bondVault.accounts(executor);
        assertEq(available, 1_000e6);
        assertEq(reserved, 0);

        _react(resolutionLogs, 11);
        assertEq(rsc.nextCallbackNonce(), 1);
    }

    function _react(Vm.Log[] memory logs, uint256 txHash) private {
        for (uint256 i; i < logs.length; ++i) {
            uint256 topic0 = logs[i].topics.length > 0 ? uint256(logs[i].topics[0]) : 0;
            uint256 topic1 = logs[i].topics.length > 1 ? uint256(logs[i].topics[1]) : 0;
            uint256 topic2 = logs[i].topics.length > 2 ? uint256(logs[i].topics[2]) : 0;
            uint256 topic3 = logs[i].topics.length > 3 ? uint256(logs[i].topics[3]) : 0;
            rsc.react(
                IReactive.LogRecord({
                    chain_id: block.chainid,
                    _contract: logs[i].emitter,
                    topic_0: topic0,
                    topic_1: topic1,
                    topic_2: topic2,
                    topic_3: topic3,
                    data: logs[i].data,
                    block_number: block.number,
                    op_code: 0,
                    block_hash: 0,
                    tx_hash: txHash,
                    log_index: i
                })
            );
        }
    }
}
