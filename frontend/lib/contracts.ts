import { parseAbi, parseAbiItem } from "viem";

export const ZERO = "0x0000000000000000000000000000000000000000" as const;
export const DYNAMIC_FEE = 8_388_608;
export const MIN_SQRT_PRICE = 4_295_128_740n;
export const MAX_SQRT_PRICE = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341n;

export const erc20Abi = parseAbi([
  "function approve(address spender,uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
]);

export const bondVaultAbi = parseAbi([
  "function deposit(uint128 amount)",
  "function accounts(address executor) view returns (uint128 available,uint128 reserved,uint128 withdrawalAmount,uint64 withdrawalAvailableAt,bool registered)",
]);

export const controllerAbi = parseAbi([
  "function nextSequence() view returns (uint64)",
  "function requestWarrantyResolution(bytes32 executionId)",
  "function claimTraderCompensation() returns (uint256)",
  "function traderClaimable(address trader) view returns (uint256)",
  "function getWarranty(bytes32 executionId) view returns ((address trader,address executor,uint128 reservedBond,uint64 openedAtBlock,uint64 resolutionBlock,uint64 snapshotBlock,uint64 sequence,bytes32 evidenceHash,uint8 state))",
]);

export const lpVaultAbi = parseAbi([
  "function claim(bytes32 executionId) returns (uint256)",
  "function balanceOfAt(address account,uint64 blockNumber) view returns (uint256)",
]);

export const routerAbi = parseAbi([
  "function executeExecutorTrade((address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) key,bool zeroForOne,uint128 amountIn,uint160 sqrtPriceLimitX96) returns (bytes32 authorizationId,uint256 amountOut)",
  "function executeProtected((address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) key,(address trader,address executor,address recipient,bytes32 poolId,bool zeroForOne,uint128 amountIn,uint128 minAmountOut,uint160 sqrtPriceLimitX96,uint64 deadline,uint64 nonce,uint8 warrantyTier) mandate,bytes signature) returns (bytes32 executionId,uint256 amountOut)",
]);

export const inventoryEvent = parseAbiItem(
  "event ExecutorTradeObserved(uint256 indexed sequence,bytes32 indexed tradeId,address indexed executor,bytes32 poolId,bool zeroForOne,uint256 amountIn,uint256 amountOut)",
);
export const protectedEvent = parseAbiItem(
  "event ProtectedSwapExecuted(uint256 indexed sequence,bytes32 indexed executionId,address indexed executor,address trader,bytes32 poolId,bool zeroForOne,uint256 amountIn,uint256 amountOut,int24 tickBefore,int24 tickAfter,uint64 snapshotBlock)",
);
export const violationEvent = parseAbiItem(
  "event ViolationOpened(bytes32 indexed executionId,bytes32 indexed evidenceHash,uint64 callbackNonce)",
);
export const clearedEvent = parseAbiItem(
  "event WarrantyCleared(bytes32 indexed executionId,uint256 releasedBond,uint64 callbackNonce)",
);
export const slashedEvent = parseAbiItem(
  "event WarrantySlashed(bytes32 indexed executionId,uint256 slashAmount,uint256 traderAmount,uint256 lpAmount,uint256 reserveAmount,uint64 callbackNonce)",
);

export type Deployment = {
  deployed: boolean;
  deployedBlock?: number;
  chainId: number;
  chainName: string;
  rpcUrl?: string;
  explorerUrl?: string;
  poolManager: `0x${string}`;
  callbackProxy: `0x${string}`;
  token0: `0x${string}`;
  token1: `0x${string}`;
  bondToken: `0x${string}`;
  lpToken: `0x${string}`;
  bondVault: `0x${string}`;
  lpVault: `0x${string}`;
  controller: `0x${string}`;
  router: `0x${string}`;
  hook: `0x${string}`;
  poolId: `0x${string}`;
  executor?: `0x${string}`;
};
