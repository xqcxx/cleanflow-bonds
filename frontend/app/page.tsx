import Link from "next/link";

const rule = [
  ["01", "Front trade", "The bonded executor trades in the user direction."],
  ["02", "Protected swap", "The trader's EIP-712 mandate executes through the 5 bps lane."],
  ["03", "Profitable unwind", "The same executor trades back inside five receipts."],
];

const proof = [
  ["EIP-712", "Trader and executor are cryptographically bound before execution."],
  ["v4 Hook", "A CREATE2-mined hook authenticates the route and selects the fee tier."],
  ["Reactive", "A stateful RSC joins three independent receipts into deterministic evidence."],
  ["Collateral", "A reserved bond has one terminal path: release or slash."],
];

export default function Home() {
  return (
    <main className="site">
      <header className="site-nav">
        <Link className="site-brand" href="#top">CLEANFLOW<span>/BONDS</span></Link>
        <nav aria-label="Primary navigation">
          <a href="#why">Why now</a>
          <a href="#mechanism">Mechanism</a>
          <a href="#architecture">Architecture</a>
          <a href="#proof">Proof</a>
        </nav>
        <Link className="launch small" href="/lab">LAUNCH APP <b>↗</b></Link>
      </header>

      <section className="site-hero" id="top">
        <div className="hero-rail"><span>MEV PROTECTION</span><i /><span>UNISWAP V4</span><i /><span>REACTIVE NETWORK</span></div>
        <div className="site-hero-copy">
          <p className="site-kicker">EXECUTION QUALITY, WITH SKIN IN THE GAME</p>
          <h1>Make the<br /><em>promise</em><br />payable.</h1>
          <p className="site-lede">CleanFlow Bonds lets routers collateralize a precise execution warranty. A bonded route earns a preferred Uniswap v4 fee. Break the rule, and the bond pays the people exposed to it.</p>
          <div className="hero-actions"><Link className="launch" href="/lab">LAUNCH THE LAB <b>↗</b></Link><a className="text-action" href="#mechanism">READ THE WARRANTY <span>↓</span></a></div>
        </div>
        <div className="hero-object" aria-label="Bond reserve diagram">
          <div className="bond-orbit"><span>100</span><small>USDC<br />RESERVED</small></div>
          <div className="orbit-label top">BONDED<br />EXECUTOR</div>
          <div className="orbit-label bottom">SIGNED<br />WARRANTY</div>
          <div className="object-caption">A fee tier is no longer a marketing claim.<br />It is backed by locked value.</div>
        </div>
      </section>

      <section className="thesis" id="why">
        <p className="site-kicker">THE GAP</p>
        <div><h2>Protection is easy to promise.<br />Recourse is hard to find.</h2><p>Execution services can advertise protected flow while retaining no collateralized consequence when their own disclosed identity extracts a prohibited profit around a user order. Traders have no contract to point at. LPs absorb harmful flow without a remedy.</p></div>
        <div className="thesis-stamp"><span>THE SHIFT</span><strong>claim<br /><i>→</i> warranty</strong></div>
      </section>

      <section className="split-statement">
        <article><span>WITHOUT CLEANFLOW</span><h3>“Trust our route.”</h3><p>An execution-quality statement with no locked collateral and no objective settlement path.</p><div className="ghost-flow"><i>ROUTER</i><b>?</b><i>TRADER</i></div></article>
        <article className="acid-statement"><span>WITH CLEANFLOW</span><h3>“Verify our warranty.”</h3><p>A named executor reserves a bond before entering the protected v4 route.</p><div className="solid-flow"><i>EXECUTOR</i><b>100 USDC</b><i>TRADER</i></div></article>
      </section>

      <section className="mechanism" id="mechanism">
        <div className="section-eyebrow"><span>01</span><p>THE MACHINE-CHECKABLE RULE</p></div>
        <div className="mechanism-heading"><h2>One narrow promise.<br />One deterministic outcome.</h2><p>CleanFlow does not claim universal sandwich detection. It enforces one published pattern inside a registered identity and protected route.</p></div>
        <div className="rule-grid">
          {rule.map(([number, title, copy]) => <article key={number}><span>{number}</span><div className="rule-icon">{number === "01" ? "→" : number === "02" ? "⊙" : "←"}</div><h3>{title}</h3><p>{copy}</p></article>)}
        </div>
        <div className="all-conditions"><b>SLASH ONLY IF ALL CONDITIONS HOLD</b><span>same executor</span><span>same pool</span><span>five-receipt window</span><span>opposite unwind</span><span>profitable round trip</span></div>
      </section>

      <section className="fee-section">
        <div><p className="site-kicker">THE INCENTIVE</p><h2>Better flow earns<br />better access.</h2><p>Collateral is reserved before execution, not after an allegation. That lets LPs distinguish accountable flow from a generic routing claim.</p></div>
        <div className="fee-board"><div><span>OBSERVABLE EXECUTOR FLOW</span><strong>30 <small>bps</small></strong></div><div className="fee-arrow">↓<small>signed mandate<br />+ reserved bond</small></div><div className="protected-fee"><span>PROTECTED CLEANFLOW LANE</span><strong>5 <small>bps</small></strong></div></div>
      </section>

      <section className="architecture" id="architecture">
        <div className="section-eyebrow"><span>02</span><p>REAL ON-CHAIN COMPONENTS</p></div>
        <h2>From signature to settlement,<br />every handoff is accountable.</h2>
        <div className="architecture-map">
          <div className="arch-node trader-node"><b>TRADER</b><span>Signs EIP-712 mandate</span></div><div className="arch-line sign">signed mandate <i>→</i></div><div className="arch-node executor-node"><b>EXECUTOR</b><span>Posts 1,000 USDC bond</span></div>
          <div className="arch-line down-left"><i>↓</i></div><div className="arch-node router-node"><b>CLEANFLOW ROUTER</b><span>Recovers signer, binds executor, reserves collateral</span></div><div className="arch-line down-right"><i>↓</i></div>
          <div className="arch-node hook-node"><b>UNISWAP V4 HOOK</b><span>Authenticates route, applies fee, emits actual receipts</span></div>
          <div className="arch-line reactive-link"><i>receipt stream →</i></div><div className="arch-node rsc-node"><b>REACTIVE RSC</b><span>Correlates event sequence and produces evidence hash</span></div>
          <div className="arch-line callback-link"><i>authenticated callback ↙</i></div><div className="arch-node controller-node"><b>CONTROLLER</b><span>Clears reservation or allocates the slash</span></div>
        </div>
      </section>

      <section className="waterfall-site">
        <div><p className="site-kicker">WHEN THE WARRANTY BREAKS</p><h2>One bond becomes<br />a concrete remedy.</h2><p>Settlement never loops through LPs. Pre-event share checkpoints determine each LP&apos;s pull claim.</p></div>
        <div className="waterfall-visual"><div className="source"><span>RESERVED BOND</span><strong>100</strong><small>demo USDC</small></div><div className="branches"><div><b>60%</b><span>TRADER</span><p>Direct claimable compensation</p></div><div><b>30%</b><span>SNAPSHOT LPs</span><p>Checkpoint-indexed pull claims</p></div><div><b>10%</b><span>RESERVE</span><p>Safety and liveness budget</p></div></div></div>
      </section>

      <section className="proof-site" id="proof">
        <div className="section-eyebrow"><span>03</span><p>NOT A DASHBOARD. A PROTOCOL.</p></div>
        <div className="proof-heading"><h2>The technical proof<br />is part of the pitch.</h2><Link className="launch dark" href="/lab">OPEN LIVE LAB <b>↗</b></Link></div>
        <div className="proof-cards">{proof.map(([title, copy], index) => <article key={title}><span>0{index + 1}</span><h3>{title}</h3><p>{copy}</p></article>)}</div>
      </section>

      <section className="limits"><div><span>HONEST SCOPE</span><h2>Precise is more<br />credible than broad.</h2></div><p>This proof covers a registered executor identity and the protected CleanFlow route. It does not detect undisclosed Sybil addresses, observe arbitrary external routers, provide transaction privacy, or resolve subjective disputes.</p></section>

      <section className="final-cta"><p className="site-kicker">READY TO WALK THE EVIDENCE</p><h2>Watch a promise<br />become enforceable.</h2><Link className="launch inverted" href="/lab">LAUNCH APP <b>↗</b></Link></section>
      <footer className="site-footer"><Link className="site-brand" href="#top">CLEANFLOW<span>/BONDS</span></Link><span>UNISWAP V4 × REACTIVE NETWORK</span><Link href="/lab">EXECUTION LAB ↗</Link></footer>
    </main>
  );
}
