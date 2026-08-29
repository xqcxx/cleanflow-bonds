# CleanFlow Bonds

CleanFlow Bonds turns a router's execution-quality promise into a collateralized warranty. A trader signs a mandate naming a bonded executor. A Uniswap v4 hook gives that accountable route a preferred fee and emits canonical receipts. If Reactive observes the same executor perform the published front-user-back round trip, an authenticated callback slashes reserved collateral to compensate the trader and pre-event LPs.

The prototype deliberately covers one machine-checkable pattern. It does not claim universal MEV detection, privacy, or Sybil resistance.

## Warranty

```text
same executor + same pool
front in user direction
-> protected user execution
-> profitable back trade in opposite direction
within five canonical receipts
= slash
```

See [`docs/warranty-spec.md`](docs/warranty-spec.md) for the complete rule and limitations.

## Development

Install pinned Solidity dependencies once:

```bash
forge install --no-git \
  v4-core=Uniswap/v4-core@rev=46c6834698c48bc4a463a86d8420f4eb1d7f3b75 \
  v4-periphery=Uniswap/v4-periphery@rev=07336f2144f522874e2c3c85e04d1d3f8d5fa471 \
  v4-hooks-public=Uniswap/v4-hooks-public@rev=f2aa843e266f8f9b34fdaf94ffb72eda5d9204f9 \
  reactive-lib=Reactive-Network/reactive-lib@rev=f6990ce3526928d039fec78855b2004ff8d65c9f \
  forge-std=foundry-rs/forge-std@rev=467ffd422ca01fed5797a4c766a1e4e3a5327902
```

```bash
forge test
forge test --match-contract CleanFlowLifecycleTest -vvvv
```

The project pins Uniswap v4, Reactive, and Foundry test dependencies under `lib/`; checkouts are intentionally excluded from Git.

## What Works

- Executor bond deposit, reserve, release, slash, and delayed withdrawal accounting.
- EIP-712 trader recovery and signed-executor binding.
- One-use mandate nonces and controller-issued opaque hook authorization IDs.
- Mined `beforeSwap` / `afterSwap` v4 hook running against the upstream PoolManager.
- A real dynamic-fee pool: standard observable executor flow is `30 bps`; protected flow is `5 bps`.
- Canonical receipts, stateful RSC correlation, evidence hash, authenticated callback nonce protection, clean clear, and violation finalization.
- Snapshot LP claims, trader claims, and 60/30/10 allocation.
- A responsive frontend execution laboratory that reads on-chain state and submits actual wallet transactions after deployment.

## Demo Assets

- [`docs/warranty-spec.md`](docs/warranty-spec.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/threat-model.md`](docs/threat-model.md)
- [`docs/demo-runbook.md`](docs/demo-runbook.md)
- [`docs/slides-outline.md`](docs/slides-outline.md)

The testnet deployment flow and video sequence are documented in the demo runbook. The local lifecycle test remains the deterministic recording fallback.
