"use client";

import { useEffect, useMemo, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  formatUnits,
  http,
  parseEventLogs,
  type Address,
  type Hex,
  type WalletClient,
} from "viem";
import {
  DYNAMIC_FEE,
  MAX_SQRT_PRICE,
  MIN_SQRT_PRICE,
  ZERO,
  bondVaultAbi,
  controllerAbi,
  erc20Abi,
  inventoryEvent,
  lpVaultAbi,
  protectedEvent,
  routerAbi,
  slashedEvent,
  violationEvent,
  clearedEvent,
  type Deployment,
} from "@/lib/contracts";

declare global {
  interface Window {
    ethereum?: { request: (args: { method: string; params?: unknown[] }) => Promise<unknown> };
  }
}

type TimelineItem = {
  sequence: number;
  label: string;
  detail: string;
  tone: "trade" | "protected" | "reactive" | "settled";
  hash: Hex;
};

type Mandate = {
  trader: Address;
  executor: Address;
  recipient: Address;
  poolId: Hex;
  zeroForOne: boolean;
  amountIn: bigint;
  minAmountOut: bigint;
  sqrtPriceLimitX96: bigint;
  deadline: bigint;
  nonce: bigint;
  warrantyTier: number;
};

const maxUint = 2n ** 256n - 1n;
const stateLabels = ["None", "Pending", "Challenged", "Cleared", "Slashed"];

function short(value?: string) {
  return value ? `${value.slice(0, 6)}...${value.slice(-4)}` : "Not available";
}

export default function ExecutionLab() {
  const [deployment, setDeployment] = useState<Deployment>();
  const [account, setAccount] = useState<Address>();
  const [executor, setExecutor] = useState("");
  const [wallet, setWallet] = useState<WalletClient>();
  const [timeline, setTimeline] = useState<TimelineItem[]>([]);
  const [sequence, setSequence] = useState(0n);
  const [availableBond, setAvailableBond] = useState(0n);
  const [reservedBond, setReservedBond] = useState(0n);
  const [frontOutput, setFrontOutput] = useState<bigint>();
  const [mandate, setMandate] = useState<Mandate>();
  const [signature, setSignature] = useState<Hex>();
  const [executionId, setExecutionId] = useState<Hex>();
  const [warrantyState, setWarrantyState] = useState(0);
  const [claimable, setClaimable] = useState(0n);
  const [lpEligible, setLpEligible] = useState(false);
  const [status, setStatus] = useState("Load a deployment to begin the execution laboratory.");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    Promise.all([
      fetch("/deployments/unichain-sepolia.json").then((response) => response.json() as Promise<Deployment>),
      fetch("/deployments/demo-accounts.json").then((response) => response.ok ? response.json() as Promise<{ executor?: Address }> : undefined),
      fetch("/deployments/violation-scenario.json").then((response) => response.ok ? response.json() as Promise<{ executionId?: Hex }> : undefined),
    ])
      .then(([value, actors, scenario]) => {
        setDeployment(value);
        setExecutor(actors?.executor ?? value.executor ?? "");
        setExecutionId(scenario?.executionId);
        setStatus(value.deployed ? "Deployment found. Connect the current scenario actor." : "Deployment required. Local tests remain available with forge.");
      })
      .catch(() => setStatus("Could not load the deployment manifest."));
  }, []);

  const chain = useMemo(() => deployment ? defineChain({
    id: deployment.chainId,
    name: deployment.chainName,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [deployment.rpcUrl || "http://127.0.0.1:8545"] } },
    blockExplorers: deployment.explorerUrl ? { default: { name: "Explorer", url: deployment.explorerUrl } } : undefined,
  }) : undefined, [deployment]);

  const publicClient = useMemo(() => chain ? createPublicClient({
    chain,
    transport: http(process.env.NEXT_PUBLIC_UNICHAIN_RPC_URL || deployment?.rpcUrl),
  }) : undefined, [chain, deployment]);

  const poolKey = useMemo(() => deployment ? {
    currency0: deployment.token0,
    currency1: deployment.token1,
    fee: DYNAMIC_FEE,
    tickSpacing: 60,
    hooks: deployment.hook,
  } : undefined, [deployment]);

  async function connect() {
    if (!window.ethereum || !chain) return setStatus("Install an injected wallet first.");
    try {
      await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: `0x${chain.id.toString(16)}` }] });
    } catch {
      setStatus(`Switch the wallet to ${chain.name}, chain ${chain.id}.`);
    }
    const nextWallet = createWalletClient({ chain, transport: custom(window.ethereum) });
    const [nextAccount] = await nextWallet.requestAddresses();
    setWallet(nextWallet);
    setAccount(nextAccount);
    setStatus(`Connected ${short(nextAccount)}. Select the step for this actor.`);
    await refresh(nextAccount);
  }

  async function refresh(currentAccount = account) {
    if (!deployment?.deployed || !publicClient) return;
    setBusy(true);
    try {
      const latest = await publicClient.getBlockNumber();
      // A demo can span more than 2,000 blocks while Reactive callbacks settle.
      // The hook/controller addresses are deployment-specific, so this remains bounded.
      const fromBlock = deployment.deployedBlock ? BigInt(deployment.deployedBlock) : 0n;
      const [nextSequence, inventory, protectedLogs, violations, slashes, clears] = await Promise.all([
        publicClient.readContract({ address: deployment.controller, abi: controllerAbi, functionName: "nextSequence" }),
        publicClient.getLogs({ address: deployment.hook, event: inventoryEvent, fromBlock }),
        publicClient.getLogs({ address: deployment.hook, event: protectedEvent, fromBlock }),
        publicClient.getLogs({ address: deployment.controller, event: violationEvent, fromBlock }),
        publicClient.getLogs({ address: deployment.controller, event: slashedEvent, fromBlock }),
        publicClient.getLogs({ address: deployment.controller, event: clearedEvent, fromBlock }),
      ]);
      setSequence(nextSequence);
      const items: TimelineItem[] = [];
      for (const log of inventory) items.push({
        sequence: Number(log.args.sequence ?? 0n),
        label: log.args.zeroForOne ? "Executor front trade" : "Executor back trade",
        detail: `${formatUnits(log.args.amountIn ?? 0n, 18)} in / ${formatUnits(log.args.amountOut ?? 0n, 18)} out`,
        tone: "trade",
        hash: log.transactionHash,
      });
      for (const log of protectedLogs) items.push({
        sequence: Number(log.args.sequence ?? 0n),
        label: "Signed protected execution",
        detail: `5 bps lane / ${formatUnits(log.args.amountIn ?? 0n, 18)} token input`,
        tone: "protected",
        hash: log.transactionHash,
      });
      for (const log of violations) items.push({ sequence: 10_000 + Number(log.logIndex), label: "Reactive evidence matched", detail: short(log.args.evidenceHash), tone: "reactive", hash: log.transactionHash });
      for (const log of slashes) items.push({ sequence: 20_000 + Number(log.logIndex), label: "Bond slashed", detail: `${formatUnits(log.args.slashAmount ?? 0n, 6)} USDC allocated`, tone: "settled", hash: log.transactionHash });
      for (const log of clears) items.push({ sequence: 20_000 + Number(log.logIndex), label: "Warranty cleared", detail: `${formatUnits(log.args.releasedBond ?? 0n, 6)} USDC released`, tone: "settled", hash: log.transactionHash });
      setTimeline(items.sort((a, b) => a.sequence - b.sequence));

      if (currentAccount) {
        const bond = await publicClient.readContract({ address: deployment.bondVault, abi: bondVaultAbi, functionName: "accounts", args: [currentAccount] });
        setAvailableBond(bond[0]);
        setReservedBond(bond[1]);
        setClaimable(await publicClient.readContract({ address: deployment.controller, abi: controllerAbi, functionName: "traderClaimable", args: [currentAccount] }));
        if (executionId) {
          const warranty = await publicClient.readContract({ address: deployment.controller, abi: controllerAbi, functionName: "getWarranty", args: [executionId] });
          const shares = await publicClient.readContract({ address: deployment.lpVault, abi: lpVaultAbi, functionName: "balanceOfAt", args: [currentAccount, warranty.snapshotBlock] });
          setLpEligible(shares > 0n);
        } else {
          setLpEligible(false);
        }
      }
      if (executionId) {
        const warranty = await publicClient.readContract({ address: deployment.controller, abi: controllerAbi, functionName: "getWarranty", args: [executionId] });
        setWarrantyState(Number(warranty.state));
      }
      setStatus(`Chain refreshed at block ${latest}.`);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Chain refresh failed.");
    } finally {
      setBusy(false);
    }
  }

  async function send(label: string, action: () => Promise<Hex>) {
    if (!publicClient) return;
    setBusy(true);
    setStatus(`${label}: confirm in wallet.`);
    try {
      const hash = await action();
      setStatus(`${label}: submitted ${short(hash)}.`);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("Transaction reverted");
      setStatus(`${label}: confirmed in block ${receipt.blockNumber}.`);
      await refresh();
      return receipt;
    } catch (error) {
      setStatus(`${label}: ${error instanceof Error ? error.message.split("\n")[0] : "failed"}`);
    } finally {
      setBusy(false);
    }
  }

  async function depositBond() {
    if (!wallet || !account || !deployment) return;
    const approval = await send("Bond approval", () => wallet.writeContract({ account, chain: null, address: deployment.bondToken, abi: erc20Abi, functionName: "approve", args: [deployment.bondVault, maxUint] }));
    if (!approval) return;
    await send("Deposit 1,000 USDC bond", () => wallet.writeContract({ account, chain: null, address: deployment.bondVault, abi: bondVaultAbi, functionName: "deposit", args: [1_000_000_000n] }));
  }

  async function runInventory(zeroForOne: boolean) {
    if (!wallet || !account || !deployment || !poolKey) return;
    const receipt = await send(zeroForOne ? "Executor front trade" : "Executor back trade", () => wallet.writeContract({
      account, chain: null,
      address: deployment.router,
      abi: routerAbi,
      functionName: "executeExecutorTrade",
      args: [poolKey, zeroForOne, zeroForOne ? 1_000_000_000_000_000_000n : (frontOutput ?? 0n), zeroForOne ? MIN_SQRT_PRICE : MAX_SQRT_PRICE],
    }));
    if (zeroForOne && receipt) {
      const parsed = parseEventLogs({ abi: [inventoryEvent], logs: receipt.logs, strict: false });
      const output = parsed[0]?.args.amountOut;
      if (output) setFrontOutput(output);
    }
  }

  async function signMandate() {
    if (!wallet || !account || !deployment || !executor) return setStatus("Enter the bonded executor address first.");
    const nextMandate: Mandate = {
      trader: account,
      executor: executor as Address,
      recipient: account,
      poolId: deployment.poolId,
      zeroForOne: true,
      amountIn: 10_000_000_000_000_000_000n,
      minAmountOut: 1n,
      sqrtPriceLimitX96: MIN_SQRT_PRICE,
      deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      nonce: BigInt(Date.now()),
      warrantyTier: 1,
    };
    try {
      const signed = await wallet.signTypedData({
        account,
        domain: { name: "CleanFlow Bonds", version: "1", chainId: deployment.chainId, verifyingContract: deployment.router },
        primaryType: "ExecutionMandate",
        types: { ExecutionMandate: [
          { name: "trader", type: "address" }, { name: "executor", type: "address" },
          { name: "recipient", type: "address" }, { name: "poolId", type: "bytes32" },
          { name: "zeroForOne", type: "bool" }, { name: "amountIn", type: "uint128" },
          { name: "minAmountOut", type: "uint128" }, { name: "sqrtPriceLimitX96", type: "uint160" },
          { name: "deadline", type: "uint64" }, { name: "nonce", type: "uint64" },
          { name: "warrantyTier", type: "uint8" },
        ] },
        message: nextMandate,
      });
      setMandate(nextMandate);
      setSignature(signed);
      setStatus("Mandate signed. Switch to the named executor wallet to submit it.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message.split("\n")[0] : "Signature rejected.");
    }
  }

  async function submitProtected(replay = false) {
    if (!wallet || !account || !deployment || !poolKey || !mandate || !signature) return;
    const receipt = await send(replay ? "Replay attempt" : "Protected execution", () => wallet.writeContract({
      account, chain: null,
      address: deployment.router,
      abi: routerAbi,
      functionName: "executeProtected",
      args: [poolKey, mandate, signature],
    }));
    if (receipt && !replay) {
      const parsed = parseEventLogs({ abi: [protectedEvent], logs: receipt.logs, strict: false });
      const id = parsed[0]?.args.executionId;
      if (id) setExecutionId(id);
    }
  }

  async function requestResolution() {
    if (!wallet || !account || !deployment || !executionId) return;
    await send("Request warranty resolution", () => wallet.writeContract({ account, chain: null, address: deployment.controller, abi: controllerAbi, functionName: "requestWarrantyResolution", args: [executionId] }));
  }

  async function claimTrader() {
    if (!wallet || !account || !deployment) return;
    await send("Claim trader compensation", () => wallet.writeContract({ account, chain: null, address: deployment.controller, abi: controllerAbi, functionName: "claimTraderCompensation" }));
  }

  async function claimLp() {
    if (!wallet || !account || !deployment || !executionId) return;
    await send("Claim LP compensation", () => wallet.writeContract({ account, chain: null, address: deployment.lpVault, abi: lpVaultAbi, functionName: "claim", args: [executionId] }));
  }

  const ready = Boolean(deployment?.deployed && wallet && account);
  const explorer = deployment?.explorerUrl;

  return (
    <main>
      <header className="masthead">
        <a className="brand" href="#top">CLEANFLOW<span>/BONDS</span></a>
        <div className={`network ${deployment?.deployed ? "live" : "offline"}`}><i />{deployment?.deployed ? deployment.chainName : "DEPLOYMENT REQUIRED"}</div>
        <button className="wallet" onClick={connect}>{account ? short(account) : "CONNECT ACTOR"}</button>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">EXECUTION QUALITY, COLLATERALIZED</p>
          <h1>A promise that<br /><em>can be slashed.</em></h1>
          <p className="lede">Bonded executors receive a preferred Uniswap v4 lane. Break the signed anti-sandwich warranty and Reactive routes the bond to the harmed trader and pre-event LPs.</p>
        </div>
        <div className="rule-card">
          <span className="rule-number">01 / THE RULE</span>
          <div className="flow-rule"><b>FRONT</b><span>→</span><b>PROTECTED</b><span>→</span><b>BACK</b></div>
          <p>Same identity. Same pool. Opposite unwind. Profitable round trip. Five-receipt window.</p>
          <div className="fee-row"><span>STANDARD <strong>30 bps</strong></span><span>÷</span><span>PROTECTED <strong>5 bps</strong></span></div>
        </div>
      </section>

      <section className="status-strip"><span className={busy ? "pulse" : ""}>{busy ? "PROCESSING" : "SYSTEM"}</span><p>{status}</p><button onClick={() => refresh()} disabled={busy}>REFRESH CHAIN</button></section>

      <section className="lab">
        <div className="section-title"><span>02</span><div><p>LIVE PROTOCOL</p><h2>Execution laboratory</h2></div></div>
        <div className="lab-grid">
          <aside className="controls">
            <label>BONDED EXECUTOR<input value={executor} onChange={(event) => setExecutor(event.target.value)} placeholder="0x..." /></label>
            <div className="actor-line"><span>CONNECTED ACTOR</span><b>{short(account)}</b></div>
            <div className="control-list">
              <button disabled={!ready || busy} onClick={depositBond}><small>01</small><span>Bond executor<strong>1,000 demo USDC</strong></span></button>
              <button disabled={!ready || busy} onClick={() => runInventory(true)}><small>02</small><span>Run front trade<strong>Executor, token0 → token1</strong></span></button>
              <button disabled={!ready || busy} onClick={signMandate}><small>03</small><span>Sign warranty<strong>Trader, EIP-712</strong></span></button>
              <button disabled={!ready || busy || !signature} onClick={() => submitProtected()}><small>04</small><span>Execute protected swap<strong>Named executor only</strong></span></button>
              <button disabled={!ready || busy || !frontOutput} onClick={() => runInventory(false)}><small>05</small><span>Run back trade<strong>Reactive match begins</strong></span></button>
              <button disabled={!ready || busy || !executionId} onClick={requestResolution}><small>06</small><span>Request resolution<strong>Permissionless</strong></span></button>
              <button disabled={!ready || busy || !signature} onClick={() => submitProtected(true)}><small>07</small><span>Attempt replay<strong>Expected: nonce revert</strong></span></button>
            </div>
          </aside>

          <div className="trace-panel">
            <div className="panel-head"><div><p>CANONICAL RECEIPTS</p><h3>Sequence trace</h3></div><strong>#{sequence.toString().padStart(3, "0")}</strong></div>
            <div className="timeline">
              {timeline.length === 0 && <div className="empty-trace"><span>∅</span><p>No canonical receipts indexed yet.</p><small>Run the Foundry lifecycle or connect a deployment.</small></div>}
              {timeline.map((item, index) => <a className={`trace ${item.tone}`} href={explorer ? `${explorer}/tx/${item.hash}` : "#"} target="_blank" rel="noreferrer" key={`${item.hash}-${index}`}>
                <i>{item.sequence < 10_000 ? String(item.sequence).padStart(2, "0") : "RX"}</i><div><b>{item.label}</b><span>{item.detail}</span></div><code>{short(item.hash)}</code>
              </a>)}
            </div>
          </div>

          <aside className="metrics">
            <div className="metric acid"><span>AVAILABLE BOND</span><strong>{formatUnits(availableBond, 6)}</strong><small>demo USDC</small></div>
            <div className="metric"><span>RESERVED</span><strong>{formatUnits(reservedBond, 6)}</strong><small>backing open warranties</small></div>
            <div className="metric"><span>WARRANTY STATE</span><strong className="state">{stateLabels[warrantyState]}</strong><small>{executionId ? short(executionId) : "No execution selected"}</small></div>
            <div className="metric"><span>TRADER CLAIMABLE</span><strong>{formatUnits(claimable, 6)}</strong><small>60% of finalized slash</small></div>
            <div className="claim-row"><button disabled={!ready || busy || claimable === 0n} onClick={claimTrader}>CLAIM TRADER</button><button disabled={!ready || busy || !executionId || !lpEligible} onClick={claimLp}>CLAIM LP</button></div>
          </aside>
        </div>
      </section>

      <section className="waterfall">
        <div className="section-title light"><span>03</span><div><p>DETERMINISTIC REMEDY</p><h2>One bond. Three recipients.</h2></div></div>
        <div className="waterfall-grid"><div className="slash-total"><span>RESERVED WARRANTY</span><b>100</b><small>demo USDC</small></div><div className="allocation trader"><span>TRADER</span><b>60%</b><p>Direct compensation for the signed protected order.</p></div><div className="allocation lp"><span>PRE-EVENT LPs</span><b>30%</b><p>Checkpointed shares prevent post-event deposits from claiming.</p></div><div className="allocation reserve"><span>SAFETY RESERVE</span><b>10%</b><p>Protocol resilience and callback liveness budget.</p></div></div>
      </section>

      <section className="proof">
        <div><p className="eyebrow">WHAT THIS PROVES</p><h2>Narrow by design.<br />Credible by construction.</h2></div>
        <div className="proof-grid"><article><b>IDENTITY</b><p>Trader recovered from EIP-712. Executor bound to the submitting account. No self-declared identity in hook data.</p></article><article><b>V4 CRAFT</b><p>Mined hook address, real PoolManager unlock settlement, canonical deltas, and per-swap dynamic fee override.</p></article><article><b>REACTIVE</b><p>Three source receipts become one evidence hash, then an authenticated, replay-protected destination callback.</p></article><article className="limit"><b>LIMIT</b><p>Known bonded identity and protected route only. No universal MEV detection, privacy, or Sybil detection claim.</p></article></div>
      </section>

      <footer><span>CLEANFLOW BONDS / PROOF OF CONCEPT</span><code>{deployment?.hook !== ZERO ? short(deployment?.hook) : "forge test --match-contract CleanFlowLifecycleTest -vvvv"}</code></footer>
    </main>
  );
}
