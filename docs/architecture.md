# Architecture

```text
Trader signs EIP-712 mandate
        |
        v
Executor -> CleanFlowRouter -> PoolManager -> CleanFlowHook
                    |                            |
                    v                            v
             CleanFlowController <------- canonical receipts
                    |
                    | source events
                    v
              CleanFlowRSC on Reactive Lasna
                    |
                    | Callback Proxy + injected RVM identity
                    v
             CleanFlowController
                    |
          trader / snapshot LPs / reserve
```

The router authenticates actors and creates one-use controller authorizations. The hook never trusts identities encoded by an arbitrary caller. It receives only an authorization ID, consumes the corresponding controller record, applies the fee tier, and records actual swap deltas.

Reactive correlates source receipts but does not custody funds or override destination lifecycle checks. The controller remains the final authorization and accounting boundary.
