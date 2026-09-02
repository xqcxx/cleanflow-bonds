// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ExecutorBondVault} from "../src/core/ExecutorBondVault.sol";
import {LpCompensationVault} from "../src/core/LpCompensationVault.sol";
import {CleanFlowController} from "../src/core/CleanFlowController.sol";
import {CleanFlowRouter} from "../src/core/CleanFlowRouter.sol";
import {IERC20} from "../src/core/TokenUtils.sol";
import {CleanFlowHook} from "../src/hook/CleanFlowHook.sol";
import {CleanFlowHookFactory} from "../src/deploy/CleanFlowHookFactory.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {DemoLiquidityManager} from "../src/mocks/DemoLiquidityManager.sol";

contract DeployUnichainScript is Script {
    using PoolIdLibrary for PoolKey;

    uint160 private constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        address callbackProxy = vm.envAddress("CALLBACK_PROXY");
        address safetyReserve = vm.envOr("SAFETY_RESERVE", deployer);
        address managerAddress = vm.envOr("POOL_MANAGER", address(0));
        uint256 callbackFunding = vm.envOr("CALLBACK_FUNDING", uint256(0.1 ether));

        vm.startBroadcast(privateKey);
        IPoolManager manager = managerAddress == address(0)
            ? IPoolManager(address(new PoolManager(deployer)))
            : IPoolManager(managerAddress);
        MockERC20 a = new MockERC20("CleanFlow Token A", "cfA", 18);
        MockERC20 b = new MockERC20("CleanFlow Token B", "cfB", 18);
        (MockERC20 token0, MockERC20 token1) = address(a) < address(b) ? (a, b) : (b, a);
        MockERC20 bondToken = new MockERC20("Demo USDC", "dUSDC", 6);
        MockERC20 lpToken = new MockERC20("CleanFlow LP", "cfLP", 18);

        ExecutorBondVault bondVault = new ExecutorBondVault(IERC20(address(bondToken)), 1 days);
        LpCompensationVault lpVault =
            new LpCompensationVault(IERC20(address(lpToken)), IERC20(address(bondToken)));
        CleanFlowController controller = new CleanFlowController(
            IERC20(address(bondToken)),
            bondVault,
            lpVault,
            callbackProxy,
            safetyReserve,
            100e6,
            5
        );
        CleanFlowRouter router = new CleanFlowRouter(manager, controller);
        CleanFlowHookFactory factory = new CleanFlowHookFactory();
        (, bytes32 salt) = factory.findSalt(manager, controller, address(router));
        CleanFlowHook hook = factory.deployHook(salt, manager, controller, address(router));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, SQRT_PRICE_1_1);
        DemoLiquidityManager liquidityManager = new DemoLiquidityManager(manager);

        bondVault.setController(address(controller));
        lpVault.setController(address(controller));
        controller.setRouter(address(router));
        controller.setHook(address(hook));
        router.setPool(address(hook), PoolId.unwrap(key.toId()));
        (bool funded,) = callbackProxy.call{value: callbackFunding}(
            abi.encodeWithSignature("depositTo(address)", address(controller))
        );
        require(funded, "callback funding failed");
        vm.stopBroadcast();

        string memory root = "deployment";
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "deployedBlock", block.number);
        vm.serializeString(root, "chainName", "Unichain Sepolia");
        vm.serializeString(root, "rpcUrl", "https://sepolia.unichain.org");
        vm.serializeString(root, "explorerUrl", "https://sepolia.uniscan.xyz");
        vm.serializeAddress(root, "deployer", deployer);
        vm.serializeAddress(root, "poolManager", address(manager));
        vm.serializeAddress(root, "callbackProxy", callbackProxy);
        vm.serializeAddress(root, "safetyReserve", safetyReserve);
        vm.serializeAddress(root, "token0", address(token0));
        vm.serializeAddress(root, "token1", address(token1));
        vm.serializeAddress(root, "bondToken", address(bondToken));
        vm.serializeAddress(root, "lpToken", address(lpToken));
        vm.serializeAddress(root, "bondVault", address(bondVault));
        vm.serializeAddress(root, "lpVault", address(lpVault));
        vm.serializeAddress(root, "controller", address(controller));
        vm.serializeAddress(root, "router", address(router));
        vm.serializeAddress(root, "hookFactory", address(factory));
        vm.serializeAddress(root, "hook", address(hook));
        vm.serializeAddress(root, "liquidityManager", address(liquidityManager));
        vm.serializeBytes32(root, "poolId", PoolId.unwrap(key.toId()));
        string memory json = vm.serializeBool(root, "deployed", true);
        vm.writeJson(json, "deployments/unichain-sepolia.json");
        vm.writeJson(json, "frontend/public/deployments/unichain-sepolia.json");
    }
}
