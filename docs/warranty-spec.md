# CleanFlow Warranty Specification

## Claim

CleanFlow makes one execution-quality promise economically enforceable. It does not detect every sandwich attack, provide transaction privacy, or identify undisclosed Sybil addresses.

## Protected Execution

A protected execution is valid only when all of the following hold:

1. The trader signs the canonical EIP-712 mandate.
2. The transaction sender is the executor named by the mandate.
3. The mandate names the configured pool and exact-input parameters.
4. The mandate nonce is unused and its deadline has not passed.
5. The executor has at least `100 USDC` of available bond.
6. The controller reserves that bond before entering the v4 PoolManager.
7. The hook consumes a one-use authorization created by the router.

## Prohibited Sequence

An execution is challenged only when one registered executor produces all three canonical receipts in the configured pool:

```text
front trade -> protected trader swap -> back trade
```

All conditions must hold:

```text
front.executor == protected.executor == back.executor
front.poolId == protected.poolId == back.poolId
front.zeroForOne == protected.zeroForOne
back.zeroForOne != protected.zeroForOne
front.sequence < protected.sequence < back.sequence
protected.sequence - front.sequence <= 5
back.sequence - protected.sequence <= 5
back.amountIn is within 5% of front.amountOut
back.amountOut >= front.amountIn + 1 unit of the starting asset
```

The RSC derives the evidence hash from the three source event identities. Near matches, unprofitable round trips, opposite ordering, different executors, different pools, and trades outside the sequence window do not violate this warranty.

## Settlement

Every protected execution reserves `100 USDC` and has exactly one terminal outcome:

- `Cleared`: the reservation returns to executor availability.
- `Slashed`: `60 USDC` becomes claimable by the trader, `30 USDC` funds snapshot LP claims, and `10 USDC` is transferred to the safety reserve.

LP eligibility is determined from shares in the block before protected execution. This excludes liquidity deposited in the execution block or later.

## Demo Parameters

| Parameter | Value |
| --- | ---: |
| Standard fee | 30 bps |
| Protected fee | 5 bps |
| Sequence window | 5 receipts |
| Round-trip tolerance | 5% |
| Profit threshold | 1 starting-asset unit |
| Reserved bond | 100 USDC |
| Trader / LP / reserve | 60% / 30% / 10% |

These are controlled prototype parameters, not claims of optimal production economics.
