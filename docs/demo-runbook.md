# Demo Runbook

## Guaranteed Recording Path

Use the deterministic lifecycle test as the recording fallback. It runs a real upstream v4 PoolManager, mined hook, EIP-712 recovery, RSC event correlation, simulated Callback Proxy boundary, slash, and claims.

```bash
forge test --match-contract CleanFlowLifecycleTest -vvvv
```

The expected proof sequence is:

```text
executor front trade
-> protected trader swap at 5 bps
-> executor profitable back trade
-> RSC evidence hash
-> authenticated open callback
-> resolution request
-> authenticated finalize callback
-> trader and LP claims
```

The same test file also proves the clean branch and source-log deduplication.

## Public Testnet Path

1. Set `PRIVATE_KEY`, `CALLBACK_PROXY`, and `POOL_MANAGER`.
2. Deploy the Unichain stack:

```bash
forge script script/DeployUnichain.s.sol:DeployUnichainScript \
  --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

3. `DeployUnichain` writes the deployment manifest to both `deployments/` and `frontend/public/deployments/`, including the public RPC and explorer URLs. `SeedDemo` writes the public actor manifest, including the executor address, to `frontend/public/deployments/demo-accounts.json`. Do not put keys in either public file.
4. Deploy the RSC on Reactive Lasna with `forge create`. This sends the payable constructor funding required for Reactive subscriptions:

```bash
forge create src/reactive/CleanFlowRSC.sol:CleanFlowRSC \
  --rpc-url "$REACTIVE_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --value 100000000000000000 \
  --constructor-args \
    1301 \
    1301 \
    "$HOOK" \
    "$CONTROLLER" \
    "$CONTROLLER" \
    1000000 \
    1000000000000000 \
  --broadcast
```

Copy the `Deployed to:` address into `deployments/reactive-lasna.json` as `rsc`. The constructor arguments are origin chain, destination chain, origin hook, origin controller, destination controller, callback gas limit, and profit threshold.

5. Obtain the actual ReactVM identity from Reactive. Bind it once from the Unichain deployer:

```bash
CONTROLLER=<controller> REACTIVE_RVM_ID=<reactvm-id> \
forge script script/ConfigureRvm.s.sol:ConfigureRvmScript \
  --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

6. Export the addresses from `deployments/unichain-sepolia.json` as `TOKEN0`, `TOKEN1`, `BOND_TOKEN`, `LP_TOKEN`, `POOL_MANAGER`, `BOND_VAULT`, `LP_VAULT`, `ROUTER`, `HOOK`, and `LIQUIDITY_MANAGER`. Then seed fixed scenario actors and real v4 liquidity:

```bash
forge script script/SeedDemo.s.sol:SeedDemoScript \
  --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

This script requires `EXECUTOR_PRIVATE_KEY`, `TRADER_PRIVATE_KEY`, `ALICE_PRIVATE_KEY`, and `BAO_PRIVATE_KEY`, in addition to the deployer `PRIVATE_KEY`.

7. Run the two canonical branches. The separate resolution request is intentional: it allows testnet blocks and Reactive delivery to progress visibly.

```bash
forge script script/RunCleanScenario.s.sol:RunCleanScenarioScript \
  --rpc-url "$UNICHAIN_RPC_URL" --broadcast

forge script script/RunViolationScenario.s.sol:RunViolationScenarioScript \
  --rpc-url "$UNICHAIN_RPC_URL" --broadcast

EXECUTION_ID=<id-from-scenario-json> \
forge script script/RequestResolution.s.sol:RequestResolutionScript \
  --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

Wait until `resolutionBlock` in the scenario manifest is reached before the final command. Reactive uses evidence to select either `clearExecution` or `finalizeViolation`.

8. Record source receipt transactions, the Reactive callback transaction, the final destination transaction, and claims before recording the video.

## Browser Lab

```bash
cd frontend
npm install
NEXT_PUBLIC_UNICHAIN_RPC_URL="$UNICHAIN_RPC_URL" npm run dev
```

The browser never invents protocol state. It reads receipts, warranty state, bond balances, and claimable compensation from deployed contracts. Each control sends a real wallet transaction.

## Five-Minute Recording

1. Show the problem and one precise warranty rule.
2. Show a pre-completed clean execution with a returned reservation.
3. In the lab, show executor bond, signature, and the protected fee lane.
4. Execute or show the three receipts: front, protected, back.
5. Show the RSC evidence hash and destination callback transaction.
6. Show the 60/30/10 waterfall and claims.
7. Reuse the mandate to show nonce replay rejection.
8. End with hook/RSC/lifecycle test and the explicit limits.
