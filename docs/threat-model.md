# Threat Model And Limits

## Guarantees Demonstrated

- The protected trader is recovered from an EIP-712 signature verified by the router.
- The executor is the actual protected-route caller and must equal the address named in that signature.
- The bond is reserved before the router enters the PoolManager.
- The hook receives an opaque controller authorization ID, not caller-supplied trader or executor identities.
- Canonical receipts are emitted from the hook after actual v4 swap deltas are known.
- The destination requires the configured Callback Proxy, expected ReactVM identity, unused callback nonce, and valid state transition.
- A reservation can be released or slashed, never both.
- LP allocation snapshots the preceding block, excluding same-transaction and later deposits.

## Explicit Limits

- The warranty observes only trades submitted through the registered CleanFlow route.
- It detects only one registered executor identity. An undisclosed second address is out of scope.
- It classifies only the published front-protected-back sequence, not every toxic or sandwich trade.
- Reactive delivery is asynchronous. The demo models the callback boundary locally and requires public callback proof after testnet deployment.
- The resolution delay is a deterministic evidence-inspection interval, not decentralized arbitration.
- Mock tokens, fixed bond size, fixed fee tiers, and fixed allocations are demo parameters.
- Native-currency pools, fee-on-transfer tokens, rebasing tokens, Permit2, and production bonding economics are not included.
