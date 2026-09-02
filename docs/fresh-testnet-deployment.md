# Fresh Testnet Deployment

This runbook replaces every CleanFlow deployment while reusing the official Uniswap v4 PoolManager and Reactive Callback Proxy. Run every command from the repository root. Commands are intentionally single-line to avoid malformed shell continuations.

## 1. Preflight

```bash
source .env
export ORIGIN_CHAIN_ID=1301
export DESTINATION_CHAIN_ID=1301
export CALLBACK_FUNDING=100000000000000000
export CALLBACK_GAS_LIMIT=1000000
export SUBSCRIPTION_FUNDING=100000000000000000
test -n "$UNICHAIN_RPC_URL" && test -n "$REACTIVE_RPC_URL" && test -n "$PRIVATE_KEY" && test -n "$EXECUTOR_PRIVATE_KEY" && test -n "$TRADER_PRIVATE_KEY" && test -n "$ALICE_PRIVATE_KEY" && test -n "$BAO_PRIVATE_KEY" && echo "environment ready"
cast chain-id --rpc-url "$UNICHAIN_RPC_URL"
cast chain-id --rpc-url "$REACTIVE_RPC_URL"
```

Expected chain IDs are `1301` and `5318007`. Confirm all five actors have Unichain Sepolia ETH before deploying or seeding.

```bash
for key in PRIVATE_KEY EXECUTOR_PRIVATE_KEY TRADER_PRIVATE_KEY ALICE_PRIVATE_KEY BAO_PRIVATE_KEY; do address=$(cast wallet address --private-key "${!key}"); echo "$key $address $(cast balance "$address" --ether --rpc-url "$UNICHAIN_RPC_URL") ETH"; done
```

The deployer also needs at least `0.1 lREACT` on Lasna plus deployment gas.

## 2. Deploy Unichain

The deployment now deposits `0.1 ETH` into the official Callback Proxy reserve for the new controller. It writes the same manifest to `deployments/` and `frontend/public/deployments/`, including RPC and explorer URLs.

```bash
forge script script/DeployUnichain.s.sol:DeployUnichainScript --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

Load the newly generated addresses. Do not continue with addresses left over from the previous deployment.

```bash
export TOKEN0=$(jq -r '.token0' deployments/unichain-sepolia.json); export TOKEN1=$(jq -r '.token1' deployments/unichain-sepolia.json); export BOND_TOKEN=$(jq -r '.bondToken' deployments/unichain-sepolia.json); export LP_TOKEN=$(jq -r '.lpToken' deployments/unichain-sepolia.json); export BOND_VAULT=$(jq -r '.bondVault' deployments/unichain-sepolia.json); export LP_VAULT=$(jq -r '.lpVault' deployments/unichain-sepolia.json); export CONTROLLER=$(jq -r '.controller' deployments/unichain-sepolia.json); export ROUTER=$(jq -r '.router' deployments/unichain-sepolia.json); export HOOK=$(jq -r '.hook' deployments/unichain-sepolia.json); export LIQUIDITY_MANAGER=$(jq -r '.liquidityManager' deployments/unichain-sepolia.json); export POOL_MANAGER=$(jq -r '.poolManager' deployments/unichain-sepolia.json); export POOL_ID=$(jq -r '.poolId' deployments/unichain-sepolia.json); export CALLBACK_PROXY=$(jq -r '.callbackProxy' deployments/unichain-sepolia.json)
```

Verify destination callback funding before creating any warranty:

```bash
cast call "$CALLBACK_PROXY" "reserves(address)(uint256)" "$CONTROLLER" --rpc-url "$UNICHAIN_RPC_URL"
cast call "$CALLBACK_PROXY" "debts(address)(uint256)" "$CONTROLLER" --rpc-url "$UNICHAIN_RPC_URL"
```

The reserve must be nonzero and debt must be zero.

## 3. Deploy Reactive

Keep `--constructor-args` last because Forge treats every following token as a constructor argument.

```bash
forge create src/reactive/CleanFlowRSC.sol:CleanFlowRSC --rpc-url "$REACTIVE_RPC_URL" --private-key "$PRIVATE_KEY" --value "$SUBSCRIPTION_FUNDING" --broadcast --constructor-args 1301 1301 "$HOOK" "$CONTROLLER" "$CONTROLLER" "$CALLBACK_GAS_LIMIT" 1000000000000000
```

Copy the `Deployed to:` address:

```bash
export RSC=0x_REPLACE_WITH_NEW_RSC
```

Write the Reactive manifest:

```bash
jq -n --arg rsc "$RSC" --arg hook "$HOOK" --arg controller "$CONTROLLER" '{chainId:5318007,originChainId:1301,destinationChainId:1301,hook:$hook,controller:$controller,rsc:$rsc}' > deployments/reactive-lasna.json
```

Verify the RSC and its three subscriptions:

```bash
cast code "$RSC" --rpc-url "$REACTIVE_RPC_URL"
export REACTIVE_RVM_ID=$(cast rpc --rpc-url "$REACTIVE_RPC_URL" rnk_getRnkAddressMapping "$RSC" | jq -r '.rvmId')
echo "$REACTIVE_RVM_ID"
cast rpc --rpc-url "$REACTIVE_RPC_URL" rnk_getSubscribers "$REACTIVE_RVM_ID" | jq --arg rsc "${RSC,,}" '[.[] | select((.rvmContract | ascii_downcase) == $rsc)]'
```

The filtered subscription list must contain two hook topics and one controller topic.

## 4. Bind RVM

```bash
forge script script/ConfigureRvm.s.sol:ConfigureRvmScript --rpc-url "$UNICHAIN_RPC_URL" --broadcast
cast call "$CONTROLLER" "expectedRvmId()(address)" --rpc-url "$UNICHAIN_RPC_URL"
```

The returned address must equal `$REACTIVE_RVM_ID`.

## 5. Seed Once

```bash
forge script script/SeedDemo.s.sol:SeedDemoScript --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

Verify the executor starts with 1,000 available demo USDC and zero reserved:

```bash
export EXECUTOR=$(jq -r '.executor' deployments/demo-accounts.json)
cast call "$BOND_VAULT" "accounts(address)(uint128,uint128,uint128,uint64,bool)" "$EXECUTOR" --rpc-url "$UNICHAIN_RPC_URL"
```

Expected first values: `1000000000` available and `0` reserved.

## 6. Complete Clean Branch

```bash
forge script script/RunCleanScenario.s.sol:RunCleanScenarioScript --rpc-url "$UNICHAIN_RPC_URL" --broadcast
export CLEAN_EXECUTION_ID=$(jq -r '.executionId' deployments/clean-scenario.json)
jq . deployments/clean-scenario.json
```

Wait until `cast block-number --rpc-url "$UNICHAIN_RPC_URL"` is at least the manifest's `resolutionBlock`, then request resolution:

```bash
export EXECUTION_ID="$CLEAN_EXECUTION_ID"
forge script script/RequestResolution.s.sol:RequestResolutionScript --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

Poll until the final line is `3` (`Cleared`):

```bash
cast call "$CONTROLLER" "warranties(bytes32)(address,address,uint128,uint64,uint64,uint64,uint64,bytes32,uint8)" "$CLEAN_EXECUTION_ID" --rpc-url "$UNICHAIN_RPC_URL"
```

Confirm the executor is back to 1,000 available and zero reserved before continuing.

```bash
cast call "$BOND_VAULT" "accounts(address)(uint128,uint128,uint128,uint64,bool)" "$EXECUTOR" --rpc-url "$UNICHAIN_RPC_URL"
```

## 7. Complete Violation Branch

Nonce `1` was used by the clean branch, so the violation uses nonce `2`.

```bash
export SCENARIO_NONCE=2
forge script script/RunViolationScenario.s.sol:RunViolationScenarioScript --rpc-url "$UNICHAIN_RPC_URL" --broadcast
export VIOLATION_EXECUTION_ID=$(jq -r '.executionId' deployments/violation-scenario.json)
export EXECUTION_ID="$VIOLATION_EXECUTION_ID"
jq . deployments/violation-scenario.json
```

Poll until the evidence hash is nonzero and the final line is `2` (`Challenged`):

```bash
cast call "$CONTROLLER" "warranties(bytes32)(address,address,uint128,uint64,uint64,uint64,uint64,bytes32,uint8)" "$VIOLATION_EXECUTION_ID" --rpc-url "$UNICHAIN_RPC_URL"
```

Once challenged and past `resolutionBlock`, request resolution exactly once:

```bash
forge script script/RequestResolution.s.sol:RequestResolutionScript --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

Poll until the final line is `4` (`Slashed`):

```bash
cast call "$CONTROLLER" "warranties(bytes32)(address,address,uint128,uint64,uint64,uint64,uint64,bytes32,uint8)" "$VIOLATION_EXECUTION_ID" --rpc-url "$UNICHAIN_RPC_URL"
```

Verify the trader's 60 demo-USDC pull claim:

```bash
export TRADER=$(jq -r '.trader' deployments/violation-scenario.json)
cast call "$CONTROLLER" "traderClaimable(address)(uint256)" "$TRADER" --rpc-url "$UNICHAIN_RPC_URL"
```

Expected value: `60000000` (60 demo USDC at six decimals).

## 8. Start the Frontend

The frontend reads the same deployment and scenario manifests generated above. Start it only after both branches are staged:

```bash
cd frontend && npm run dev
```

Open `http://localhost:3000/lab`, connect the executor, and select `REFRESH CHAIN`. The latest violation execution is selected automatically. Connect the trader wallet when demonstrating the 60 demo-USDC claim.

## Recovery Rule

Do not rerun a scenario with the same mandate nonce. Do not issue repeated resolution requests while Reactive is delayed. Check the source receipt, RVM head, callback funding reserve, callback debt, and warranty state first.
