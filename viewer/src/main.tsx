import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { createRoot } from 'react-dom/client'
import { formatUnits, zeroHash } from 'viem'
import { deployment, snapshot, ReadIssue, type Snapshot } from './read'
import { DemoControls } from './controls'
import './style.css'

const report =
  'https://github.com/abdraufdele/Unison/blob/a11c24b5ba413ee101c9807c465df746394838c9/docs/M6-COMPARISON.md'
const phases = ['Draft', 'Accepted', 'Funded', 'Cancelled', 'Active', 'Terminated', 'Expired']
const reasons = [
  'Awaiting activation',
  'Clock stopped',
  'Period ended',
  'No matching live position',
  'Below minimum liquidity',
  'Opening band uncovered',
  'Range outside permitted bounds',
  'Tick outside position',
]
const units = (n: bigint, d: number) => formatUnits(n, d)
const number = (n: bigint) => n.toLocaleString('en-US')
const timestamp = (n: bigint) => (n === 0n ? 'Unset' : n.toString() + ' s')
const range = (l: number, u: number) => '[' + l + ', ' + u + ')'

function useAgreement() {
  const [data, setData] = useState<Snapshot>()
  const [issue, setIssue] = useState<ReadIssue>()
  const [busy, setBusy] = useState(true)
  const reading = useRef(false)
  const queued = useRef(false)
  const key = useRef('')
  const refresh = useCallback(async () => {
    if (reading.current) {
      queued.current = true
      return
    }
    reading.current = true
    setBusy(true)
    try {
      const manifest = await deployment()
      const identity = JSON.stringify(manifest)
      if (key.current !== identity) {
        setData(undefined)
        key.current = identity
      }
      const next = await snapshot(manifest)
      setData(next)
      setIssue(undefined)
    } catch (err) {
      const problem =
        err instanceof ReadIssue
          ? err
          : new ReadIssue(
              'Contract read failed',
              'Refresh to retry the complete block. ' +
                (err instanceof Error ? err.message.split('\n')[0] : 'RPC request failed.')
            )
      if (problem.discard) setData(undefined)
      setIssue(problem)
    } finally {
      reading.current = false
      setBusy(false)
      if (queued.current) {
        queued.current = false
        void refresh()
      }
    }
  }, [])
  useEffect(() => {
    void refresh()
    const timer = setInterval(refresh, 8000)
    return () => clearInterval(timer)
  }, [refresh])
  return { data, issue, busy, refresh }
}

function Rows({ items }: { items: [string, ReactNode][] }) {
  return (
    <dl>
      {items.map(([label, value]) => (
        <div key={label}>
          <dt>{label}</dt>
          <dd>{value}</dd>
        </div>
      ))}
    </dl>
  )
}
function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section id={id} className="panel">
      <h2>{title}</h2>
      {children}
    </section>
  )
}
function Data({ s }: { s: Snapshot }) {
  const activeOnce = s.start !== 0n
  const livePosition = s.position !== zeroHash
  const b = (n: bigint) => units(n, s.tokenB.decimals) + ' B'
  const [qualifies, bits] = s.qualification
  const duration = BigInt(s.terms.parameters.duration)
  const state = phases[s.phase]
  const addresses = s.m.addresses
  return (
    <>
      <div className="summary">
        <div className="clock">
          <div className="clocktop">
            <span>Service clock</span>
            <span className="pill">{state}</span>
          </div>
          <div className="time">
            <strong>{s.projected.toString()}</strong>
            <span>/ {duration.toString()} s</span>
          </div>
          <progress
            aria-label="Projected qualifying seconds of original duration"
            value={Number(s.projected)}
            max={Number(duration)}
          />
          <div className="clockfoot">
            <span>Projected at block</span>
            <span>{s.persisted.toString()} s persisted</span>
          </div>
        </div>
        <div className="earned">
          <span>Earned compensation</span>
          <strong>{b(s.earned)}</strong>
          <div>of {b(s.funded)} funded</div>
          <hr />
          <span>
            Claimed <b>{b(s.claimed)}</b>
          </span>
        </div>
      </div>
      <div className="twocol">
        <Section id="settlement" title="Compensation">
          <Rows
            items={[
              ['Funded budget', b(s.funded)],
              ['Earned', b(s.earned)],
              ['Claimed', b(s.claimed)],
              ['Unpaid earned reserve', b(s.reserved)],
              ['Claimable now', b(s.claimable)],
              ['Refunded', b(s.refunded)],
              ['Refundable now', b(s.refundable)],
            ]}
          />
        </Section>
        <Section id="position" title="Liquidity position">
          <div className={'qual ' + (qualifies ? 'yes' : '')}>
            <b>{qualifies ? 'Qualifying' : 'Not qualifying'}</b>
            {!qualifies && <p>{reasons.filter((_, i) => bits & (1 << i)).join(' · ')}</p>}
          </div>
          <Rows
            items={[
              ['Opening band', activeOnce ? range(s.lo, s.hi) : 'Set at activation'],
              ['Position ticks', livePosition ? range(s.pl, s.pu) : 'No installed position'],
              ['Current core tick', s.core[1].toString()],
              ['Owned liquidity (L)', number(s.core[3])],
              ['Pool active liquidity (L)', number(s.core[2])],
            ]}
          />
        </Section>
      </div>
      <Section id="custody" title="Token custody">
        <table>
          <thead>
            <tr>
              <th>Contract</th>
              <th>Mock A</th>
              <th>Mock B</th>
            </tr>
          </thead>
          <tbody>
            {(['vault', 'escrow'] as const).map((k) => (
              <tr key={k}>
                <th>{k === 'vault' ? 'Agreement vault' : 'Compensation escrow'}</th>
                <td>{units(s.tokenA[k], s.tokenA.decimals)}</td>
                <td>{units(s.tokenB[k], s.tokenB.decimals)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>
      <Section id="terms" title="Agreement details">
        <Rows
          items={[
            ['Agreement ID', s.terms.agreementId],
            ['Terms revision', s.terms.revision.toString()],
            ['Terms hash', s.hash],
            ['Lifecycle', state],
            ['Accepted revision · treasury / manager', s.consentT.toString() + ' / ' + s.consentM.toString()],
            ['Treasury', s.terms.treasury],
            ['Fixed treasury recipient', s.terms.treasuryRecipient],
            ['Manager', s.terms.manager],
            ['Fixed manager recipient', s.terms.managerRecipient],
            ['Original duration', duration.toString() + ' s'],
            ['Activation cutoff', timestamp(s.terms.activationCutoff)],
            ['Activation', timestamp(s.start)],
            ['Scheduled end', timestamp(s.end)],
            ['Effective stop', timestamp(s.stop)],
          ]}
        />
      </Section>
      <Section id="bindings" title="Pool and deployment">
        <Rows
          items={[
            ['Pool ID', s.poolId],
            ['Pool manager', addresses.core],
            ['Position owner · vault', addresses.vault],
            ['Position ID', livePosition ? s.position : 'No installed position'],
            ['Position salt', activeOnce ? s.salt : 'Unset'],
            ['Fixed fee / tick spacing', s.terms.parameters.fee + ' / ' + s.terms.parameters.tickSpacing],
            ['Service hook', addresses.hook],
            ['Compensation escrow', addresses.escrow],
            ['Token A', addresses.tokenA],
            ['Token B', addresses.tokenB],
            ['Chain ID', s.m.chainId],
            ['Run ID', s.m.runId],
            ['Build SHA-256', s.m.buildId],
            ['Read block hash', s.block.hash],
          ]}
        />
      </Section>
    </>
  )
}

function App() {
  const { data, issue, busy, refresh } = useAgreement()
  return (
    <>
      <header>
        <div className="top">
          <a className="brand" href="#main">
            <i aria-hidden="true">∪</i>Unison
          </a>
          <span className="network">
            Local Anvil <b>·</b> Mock assets
          </span>
        </div>
      </header>
      <main id="main">
        <div className="title">
          <div>
            <div className="context">Treasury / Agreements</div>
            <h1>C1 liquidity agreement</h1>
          </div>
          <button disabled={busy} onClick={refresh}>
            {busy ? 'Reading block…' : 'Refresh reads'}
          </button>
        </div>
        <div className={'fresh ' + (issue ? 'warn' : '')} aria-live="polite">
          {data ? (
            <>
              {issue ? 'Stale snapshot' : 'Last successful read'} · Block #{data.block.number.toString()} ·
              Chain time {data.block.timestamp.toString()} s · Checked {data.readTime.toLocaleTimeString()}
            </>
          ) : issue ? (
            'No verified snapshot'
          ) : (
            'Reading the deployment and block…'
          )}
        </div>
        {issue && (
          <div className="alert" role="alert">
            <strong>{issue.title}</strong>
            <p>{issue.message}</p>
          </div>
        )}
        {data && <DemoControls key={data.m.runId} s={data} stale={!!issue} refresh={refresh} />}
        {data && <Data s={data} />}
        <aside>
          <h2>What the agreement measures</h2>
          <p>
            Earned pay becomes paid when the manager receives it. Unpaid earnings stay reserved through a
            treasury refund. The treasury can withdraw principal while the manager payment route is blocked.
          </p>
          <p>
            Service pay follows the agreed position conditions. A passive qualifying position earns, and an
            extended range can qualify outside the opening band. Profit and manager effort are separate.
          </p>
          <p>
            The M6 comparison found matching liquidity delivery under the bounded retainer. Economic
            justification remains open. <a href={report}>Read the M6 report</a>
          </p>
        </aside>
        <div id="run-management" />
      </main>
    </>
  )
}
createRoot(document.getElementById('root')!).render(<App />)
