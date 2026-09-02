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

contract RunViolationScenarioScript is Script {
    uint160 private constant MIN_SQRT_PRICE = 4_295_128_740;
    // Uniswap v4 requires the price limit to be strictly inside TickMath's maximum.
    uint160 private constant MAX_SQRT_PRICE = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341;

    function run() external {
        uint256 executorKey = vm.envUint("EXECUTOR_PRIVATE_KEY");
        uint256 traderKey = vm.envUint("TRADER_PRIVATE_KEY");
        address executor = vm.addr(executorKey);
        address trader = vm.addr(traderKey);
        CleanFlowRouter router = CleanFlowRouter(vm.envAddress("ROUTER"));
        CleanFlowController controller = CleanFlowController(vm.envAddress("CONTROLLER"));
        PoolKey memory key = _poolKey();

        vm.startBroadcast(executorKey);
        (, uint256 frontOutput) = router.executeExecutorTrade(key, true, 1e18, MIN_SQRT_PRICE);
        vm.stopBroadcast();

        CleanFlowTypes.ExecutionMandate memory mandate = CleanFlowTypes.ExecutionMandate({
            trader: trader,
            executor: executor,
            recipient: trader,
            poolId: vm.envBytes32("POOL_ID"),
            zeroForOne: true,
            amountIn: 10e18,
            minAmountOut: 1,
            sqrtPriceLimitX96: MIN_SQRT_PRICE,
            deadline: uint64(block.timestamp + 1 hours),
            nonce: uint64(vm.envOr("SCENARIO_NONCE", uint256(1))),
            warrantyTier: 1
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(traderKey, router.mandateDigest(mandate));

        vm.startBroadcast(executorKey);
        (bytes32 executionId,) = router.executeProtected(key, mandate, abi.encodePacked(r, s, v));
        router.executeExecutorTrade(key, false, uint128(frontOutput), MAX_SQRT_PRICE);
        vm.stopBroadcast();

        CleanFlowTypes.Warranty memory warranty = controller.getWarranty(executionId);
        string memory root = "violation";
        vm.serializeAddress(root, "trader", trader);
        vm.serializeAddress(root, "executor", executor);
        vm.serializeUint(root, "resolutionBlock", warranty.resolutionBlock);
        vm.serializeUint(root, "frontOutput", frontOutput);
        string memory json = vm.serializeBytes32(root, "executionId", executionId);
        vm.writeJson(json, "deployments/violation-scenario.json");
        vm.writeJson(json, "frontend/public/deployments/violation-scenario.json");
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
}
