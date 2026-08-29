// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CleanFlowTypes} from "../../src/core/CleanFlowTypes.sol";
import {ExecutorBondVault} from "../../src/core/ExecutorBondVault.sol";
import {LpCompensationVault} from "../../src/core/LpCompensationVault.sol";
import {CleanFlowController} from "../../src/core/CleanFlowController.sol";
import {CleanFlowRouter} from "../../src/core/CleanFlowRouter.sol";
import {IERC20} from "../../src/core/TokenUtils.sol";
import {CleanFlowHook} from "../../src/hook/CleanFlowHook.sol";
import {CleanFlowHookFactory} from "../../src/deploy/CleanFlowHookFactory.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {DemoLiquidityManager} from "../../src/mocks/DemoLiquidityManager.sol";
import {CleanFlowRSC} from "../../src/reactive/CleanFlowRSC.sol";

contract CleanFlowV4Test is Test {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;
    uint128 internal constant RESERVATION = 100e6;
    uint256 internal constant TRADER_KEY = 0xA11CE;
    uint256 internal constant EXECUTOR_KEY = 0xB0B;
    address internal constant CALLBACK_PROXY = address(0xCA11BAC);
    address internal constant SAFETY_RESERVE = address(0x5AFE);
    address internal constant ALICE = address(0xA71CE);

    address internal trader;
    address internal executor;
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockERC20 internal bondToken;
    MockERC20 internal lpToken;
    PoolManager internal manager;
    ExecutorBondVault internal bondVault;
    LpCompensationVault internal lpVault;
    CleanFlowController internal controller;
    CleanFlowRouter internal router;
    CleanFlowHook internal hook;
    CleanFlowRSC internal rsc;
    PoolKey internal key;

    function setUp() public virtual {
        trader = vm.addr(TRADER_KEY);
        executor = vm.addr(EXECUTOR_KEY);
        vm.roll(10);

        manager = new PoolManager(address(this));
        (token0, token1) = _deploySortedPoolTokens();
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
        router = new CleanFlowRouter(manager, controller);
        CleanFlowHookFactory factory = new CleanFlowHookFactory();
        (address predictedHook, bytes32 salt) = factory.findSalt(manager, controller, address(router));
        hook = factory.deployHook(salt, manager, controller, address(router));
        assertEq(address(hook), predictedHook);

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, SQRT_PRICE_1_1);

        bytes32 poolId = PoolId.unwrap(key.toId());
        bondVault.setController(address(controller));
        lpVault.setController(address(controller));
        controller.setRouter(address(router));
        controller.setHook(address(hook));
        rsc = new CleanFlowRSC(
            block.chainid,
            block.chainid,
            address(hook),
            address(controller),
            address(controller),
            1_000_000,
            1e15
        );
        controller.setExpectedRvmId(address(rsc));
        router.setPool(address(hook), poolId);

        _seedLpSnapshots();
        _seedExecutorBond();
        _seedPoolLiquidity();
        _seedSwapActors();
    }

    function test_RealPoolExecutesSignatureBoundProtectedSwap() public {
        CleanFlowTypes.ExecutionMandate memory mandate = _mandate(0, 10e18);
        bytes memory signature = _signMandate(mandate);
        uint256 traderBefore = token1.balanceOf(trader);

        vm.prank(executor);
        (bytes32 executionId, uint256 amountOut) = router.executeProtected(key, mandate, signature);

        assertGt(amountOut, 0);
        assertEq(token1.balanceOf(trader) - traderBefore, amountOut);
        assertEq(controller.nextSequence(), 1);
        assertEq(uint8(controller.getWarranty(executionId).state), uint8(CleanFlowTypes.WarrantyState.Pending));
        assertEq(controller.getWarranty(executionId).reservedBond, RESERVATION);
    }

    function test_ReplayedMandateAndWrongExecutorFail() public {
        CleanFlowTypes.ExecutionMandate memory mandate = _mandate(7, 2e18);
        bytes memory signature = _signMandate(mandate);

        vm.expectRevert(CleanFlowRouter.InvalidMandate.selector);
        router.executeProtected(key, mandate, signature);

        vm.prank(executor);
        router.executeProtected(key, mandate, signature);
        vm.prank(executor);
        vm.expectRevert(CleanFlowRouter.NonceAlreadyUsed.selector);
        router.executeProtected(key, mandate, signature);
    }

    function test_RealFrontProtectedBackSequenceIsProfitable() public {
        vm.prank(executor);
        (, uint256 frontOutput) = router.executeExecutorTrade(
            key,
            true,
            1e18,
            TickMath.MIN_SQRT_PRICE + 1
        );

        CleanFlowTypes.ExecutionMandate memory mandate = _mandate(11, 10e18);
        bytes memory signature = _signMandate(mandate);
        vm.prank(executor);
        router.executeProtected(key, mandate, signature);

        vm.prank(executor);
        (, uint256 backOutput) = router.executeExecutorTrade(
            key,
            false,
            uint128(frontOutput),
            TickMath.MAX_SQRT_PRICE - 1
        );

        assertEq(controller.nextSequence(), 3);
        assertGt(backOutput, 1e18);
    }

    function _seedLpSnapshots() private {
        lpToken.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        lpToken.approve(address(lpVault), type(uint256).max);
        lpVault.deposit(100e18);
        vm.stopPrank();
        vm.roll(11);
    }

    function _seedExecutorBond() private {
        bondToken.mint(executor, 1_000e6);
        vm.startPrank(executor);
        bondToken.approve(address(bondVault), type(uint256).max);
        bondVault.deposit(1_000e6);
        vm.stopPrank();
    }

    function _seedPoolLiquidity() private {
        DemoLiquidityManager liquidityManager = new DemoLiquidityManager(manager);
        token0.mint(address(this), 1e30);
        token1.mint(address(this), 1e30);
        token0.approve(address(liquidityManager), type(uint256).max);
        token1.approve(address(liquidityManager), type(uint256).max);
        liquidityManager.addLiquidity(key, -60_000, 60_000, 1e21, keccak256("demo-liquidity"));
    }

    function _seedSwapActors() private {
        token0.mint(trader, 1e24);
        token0.mint(executor, 1e24);
        token1.mint(executor, 1e24);
        vm.prank(trader);
        token0.approve(address(router), type(uint256).max);
        vm.startPrank(executor);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function _mandate(uint64 nonce, uint128 amountIn)
        internal
        view
        returns (CleanFlowTypes.ExecutionMandate memory)
    {
        return CleanFlowTypes.ExecutionMandate({
            trader: trader,
            executor: executor,
            recipient: trader,
            poolId: PoolId.unwrap(key.toId()),
            zeroForOne: true,
            amountIn: amountIn,
            minAmountOut: 1,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1,
            deadline: uint64(block.timestamp + 1 hours),
            nonce: nonce,
            warrantyTier: 1
        });
    }

    function _signMandate(CleanFlowTypes.ExecutionMandate memory mandate) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TRADER_KEY, router.mandateDigest(mandate));
        return abi.encodePacked(r, s, v);
    }

    function _deploySortedPoolTokens() private returns (MockERC20 first, MockERC20 second) {
        MockERC20 a = new MockERC20("Token A", "TKA", 18);
        MockERC20 b = new MockERC20("Token B", "TKB", 18);
        return address(a) < address(b) ? (a, b) : (b, a);
    }
}
