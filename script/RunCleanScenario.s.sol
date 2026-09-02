// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CleanFlowTypes} from "../src/core/CleanFlowTypes.sol";
import {CleanFlowController} from "../src/core/CleanFlowController.sol";
import {CleanFlowRouter} from "../src/core/CleanFlowRouter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract RunCleanScenarioScript is Script {
    uint160 private constant MIN_SQRT_PRICE = 4_295_128_740;

    function run() external {
        uint256 executorKey = vm.envUint("EXECUTOR_PRIVATE_KEY");
        uint256 traderKey = vm.envUint("TRADER_PRIVATE_KEY");
        address executor = vm.addr(executorKey);
        address trader = vm.addr(traderKey);
        CleanFlowRouter router = CleanFlowRouter(vm.envAddress("ROUTER"));
        CleanFlowController controller = CleanFlowController(vm.envAddress("CONTROLLER"));
        PoolKey memory key = _poolKey();

        CleanFlowTypes.ExecutionMandate memory mandate = _mandate(trader, executor, router, key, 1);
        bytes32 digest = router.mandateDigest(mandate);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(traderKey, digest);

        vm.startBroadcast(executorKey);
        (bytes32 executionId,) = router.executeProtected(key, mandate, abi.encodePacked(r, s, v));
        vm.stopBroadcast();

        CleanFlowTypes.Warranty memory warranty = controller.getWarranty(executionId);
        string memory root = "clean";
        vm.serializeAddress(root, "trader", trader);
        vm.serializeAddress(root, "executor", executor);
        vm.serializeUint(root, "resolutionBlock", warranty.resolutionBlock);
        string memory json = vm.serializeBytes32(root, "executionId", executionId);
        vm.writeJson(json, "deployments/clean-scenario.json");
        vm.writeJson(json, "frontend/public/deployments/clean-scenario.json");
    }

    function _poolKey() private returns (PoolKey memory key) {
        key = PoolKey({
            currency0: Currency.wrap(address(MockERC20(vm.envAddress("TOKEN0")))),
            currency1: Currency.wrap(address(MockERC20(vm.envAddress("TOKEN1")))),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(vm.envAddress("HOOK"))
        });
    }

    function _mandate(address trader, address executor, CleanFlowRouter router, PoolKey memory key, uint64 nonce)
        private
        view
        returns (CleanFlowTypes.ExecutionMandate memory)
    {
        return CleanFlowTypes.ExecutionMandate({
            trader: trader,
            executor: executor,
            recipient: trader,
            poolId: vm.envBytes32("POOL_ID"),
            zeroForOne: true,
            amountIn: 10e18,
            minAmountOut: 1,
            sqrtPriceLimitX96: MIN_SQRT_PRICE,
            deadline: uint64(block.timestamp + 1 hours),
            nonce: nonce,
            warrantyTier: 1
        });
    }
}
