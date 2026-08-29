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

3. Copy `deployments/unichain-sepolia.json` into `frontend/public/deployments/` and add `deployed: true`, chain metadata, and seeded actor addresses.
4. Deploy the RSC on Reactive Lasna with the actual hook and controller addresses:

```bash
ORIGIN_CHAIN_ID=1301 DESTINATION_CHAIN_ID=1301 \
HOOK=<hook> CONTROLLER=<controller> \
forge script script/DeployReactive.s.sol:DeployReactiveScript \
  --rpc-url "$REACTIVE_RPC_URL" --broadcast
```

5. Obtain the actual ReactVM identity from Reactive. Bind it once from the Unichain deployer:

```bash
CONTROLLER=<controller> REACTIVE_RVM_ID=<reactvm-id> \
forge script script/ConfigureRvm.s.sol:ConfigureRvmScript \
  --rpc-url "$UNICHAIN_RPC_URL" --broadcast
```

6. Seed the executor with `1,000` demo USDC and both LPs before protected execution. Add v4 liquidity through `DemoLiquidityManager`.
7. Record source receipt transactions, the Reactive callback transaction, the final destination transaction, and claims before recording the video.

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
