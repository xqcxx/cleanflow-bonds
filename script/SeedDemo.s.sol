// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ExecutorBondVault} from "../src/core/ExecutorBondVault.sol";
import {LpCompensationVault} from "../src/core/LpCompensationVault.sol";
import {CleanFlowRouter} from "../src/core/CleanFlowRouter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {DemoLiquidityManager} from "../src/mocks/DemoLiquidityManager.sol";

/// @notice Seeds fixed named actors and real v4 liquidity for the recorded testnet scenario.
contract SeedDemoScript is Script {
    uint256 private constant EXECUTOR_BOND = 1_000e6;
    uint256 private constant LP_SHARES = 100e18;
    uint256 private constant ACTOR_SWAP_BALANCE = 100_000e18;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 executorKey = vm.envUint("EXECUTOR_PRIVATE_KEY");
        uint256 traderKey = vm.envUint("TRADER_PRIVATE_KEY");
        uint256 aliceKey = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 baoKey = vm.envUint("BAO_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address executor = vm.addr(executorKey);
        address trader = vm.addr(traderKey);
        address alice = vm.addr(aliceKey);
        address bao = vm.addr(baoKey);

        MockERC20 token0 = MockERC20(vm.envAddress("TOKEN0"));
        MockERC20 token1 = MockERC20(vm.envAddress("TOKEN1"));
        MockERC20 bondToken = MockERC20(vm.envAddress("BOND_TOKEN"));
        MockERC20 lpToken = MockERC20(vm.envAddress("LP_TOKEN"));
        ExecutorBondVault bondVault = ExecutorBondVault(vm.envAddress("BOND_VAULT"));
        LpCompensationVault lpVault = LpCompensationVault(vm.envAddress("LP_VAULT"));
        CleanFlowRouter router = CleanFlowRouter(vm.envAddress("ROUTER"));
        DemoLiquidityManager liquidityManager = DemoLiquidityManager(vm.envAddress("LIQUIDITY_MANAGER"));
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address hook = vm.envAddress("HOOK");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hook)
        });

        // The deployer owns all demo token contracts and funds controlled scenario actors.
        vm.startBroadcast(deployerKey);
        token0.mint(deployer, 1_000_000e18);
        token1.mint(deployer, 1_000_000e18);
        token0.mint(executor, ACTOR_SWAP_BALANCE);
        token1.mint(executor, ACTOR_SWAP_BALANCE);
        token0.mint(trader, ACTOR_SWAP_BALANCE);
        bondToken.mint(executor, EXECUTOR_BOND);
        lpToken.mint(alice, LP_SHARES * 60 / 100);
        lpToken.mint(bao, LP_SHARES * 40 / 100);
        token0.approve(address(liquidityManager), type(uint256).max);
        token1.approve(address(liquidityManager), type(uint256).max);
        liquidityManager.addLiquidity(key, -60_000, 60_000, 1e21, keccak256("cleanflow-demo-liquidity"));
        vm.stopBroadcast();

        vm.startBroadcast(executorKey);
        bondToken.approve(address(bondVault), type(uint256).max);
        bondVault.deposit(uint128(EXECUTOR_BOND));
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(traderKey);
        token0.approve(address(router), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(aliceKey);
        lpToken.approve(address(lpVault), type(uint256).max);
        lpVault.deposit(LP_SHARES * 60 / 100);
        vm.stopBroadcast();

        vm.startBroadcast(baoKey);
        lpToken.approve(address(lpVault), type(uint256).max);
        lpVault.deposit(LP_SHARES * 40 / 100);
        vm.stopBroadcast();

        string memory root = "scenario";
        vm.serializeAddress(root, "deployer", deployer);
        vm.serializeAddress(root, "executor", executor);
        vm.serializeAddress(root, "trader", trader);
        vm.serializeAddress(root, "alice", alice);
        string memory json = vm.serializeAddress(root, "bao", bao);
        vm.writeJson(json, "deployments/demo-accounts.json");
        vm.writeJson(json, "frontend/public/deployments/demo-accounts.json");
    }
}
