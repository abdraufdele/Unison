import { useRef, useState } from 'react'
import { formatUnits } from 'viem'
import { confirmBlock, endpoint, type Snapshot } from './read'

type Header = { number: string; timestamp: string; hash: string }
type Event = {
  name: string
  args: Record<string, string | boolean>
  block: string
  transactionHash: string
  transactionIndex: string
  logIndex: string
}
type Interval = {
  from: string
  to: string
  kind: string
  qualified: boolean
  reasons: string[]
  secondsCredited: string
  cumulativeQ: string
}
type Movement = {
  kind: string
  token: string
  amount: string
  vaultPrincipalDelta?: string
  vaultFeeDelta?: string
  eventIndex: string
}
type Report = {
  schema: string
  runId: string
  buildId: string
  chainId: string
  addresses: Record<string, string>
  termsHash: string
  terms: { revision: string; agreementId: string }
  coverage: { deployment: Header; fundedAnchor: Header; asOf: Header }
  tokens: { address: string; decimals: string; symbol: string }[]
  custodyAtAsOf: Record<string, { vault: string; escrow: string }>
  derived: Record<string, string>
  contractReads: Record<string, string>
  intervals: Interval[]
  movements: Movement[]
  reconciliation: string
  closeEventEmitted: boolean
  knownFailedReceipts: { action: string; block: string; hash: string; error: string }[]
  events: Event[]
  limitations: string[]
}

function reconcile(r: Report, s: Snapshot) {
  if (r.schema !== 'unison.c1.statement.v1' || r.buildId !== s.m.buildId)
    throw Error('Unsupported statement schema or build.')
  if (
    r.runId !== s.m.runId ||
    r.terms.agreementId !== s.m.runId ||
    r.chainId !== String(s.m.chainId) ||
    r.termsHash !== s.hash ||
    r.terms.revision !== String(s.terms.revision) ||
    r.coverage.asOf.hash !== s.block.hash ||
    r.coverage.asOf.number !== String(s.block.number) ||
    r.coverage.asOf.timestamp !== String(s.block.timestamp) ||
    r.coverage.fundedAnchor.hash !== s.m.anchor.hash ||
    Object.entries(s.m.addresses).some(([role, addr]) => r.addresses[role] !== addr) ||
    [s.tokenA, s.tokenB].some(
      (token, i) =>
        r.tokens[i]?.decimals !== String(token.decimals) ||
        r.tokens[i]?.address !== s.m.addresses[i === 0 ? 'tokenA' : 'tokenB']
    )
  )
    throw Error('Statement identity differs from the displayed agreement or block.')
  if (
    [s.tokenA, s.tokenB].some((t, i) => {
      const custody = r.custodyAtAsOf[r.tokens[i].address]
      return custody.vault !== String(t.vault) || custody.escrow !== String(t.escrow)
    })
  )
    throw Error('Statement custody differs from block-pinned balances.')
  const expected = {
    ownedLiquidity: s.core[3],
    q: s.projected,
    persistedQ: s.persisted,
    earned: s.earned,
    claimed: s.claimed,
    refunded: s.refunded,
    reserved: s.reserved,
    claimable: s.claimable,
    refundable: s.refundable,
    funded: s.funded,
    escrowB: s.tokenB.escrow,
    start: s.start,
    end: s.end,
    effectiveStop: s.stop,
  }
  if (
    r.reconciliation !== 'matched' ||
    Object.entries(expected).some(([k, n]) => r.derived[k] !== String(n) || r.contractReads[k] !== String(n))
  )
    throw Error('Event calculation differs from the displayed block-pinned contract reads.')
}

export function AgreementStatement({ s, stale }: { s: Snapshot; stale: boolean }) {
  const [report, setReport] = useState<Report>()
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const inFlight = useRef(false)
  async function prepare() {
    if (stale || inFlight.current) return
    inFlight.current = true
    setLoading(true)
    setReport(undefined)
    setError('')
    try {
      const url = new URL('/statement/' + s.m.runId + '/' + s.block.number + '/' + s.block.hash, endpoint)
      const res = await fetch(url, { cache: 'no-store', signal: AbortSignal.timeout(20000) })
      if (!res.ok) {
        const reason = await res.json().catch(() => null)
        throw Error(
          reason?.message ||
            'Statement endpoint unavailable. Check that the launcher supports historical statements.'
        )
      }
      const data: Report = await res.json()
      reconcile(data, s)
      await confirmBlock(s.block.number, s.block.hash)
      setReport(data)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Historical reads failed.')
    } finally {
      inFlight.current = false
      setLoading(false)
    }
  }
  function download() {
    if (!report || stale) return
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(report, null, 2) + '\n'], { type: 'application/json' })
    )
    const a = document.createElement('a')
    a.href = url
    a.download = 'unison-' + report.runId + '-' + report.coverage.asOf.number + '.json'
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  const b = (n: string) => formatUnits(BigInt(n), s.tokenB.decimals) + ' B'
  const activation = report?.events.find((e) => e.name === 'Activated')?.args
  const opening = report?.events.find((e) => e.name === 'OpeningFixed')?.args
  return (
    <section className="panel" id="statement">
      <h2>Agreement statement</h2>
      <p>Reconstruct service and payments through displayed block #{s.block.number.toString()}.</p>
      {!report && (
        <button disabled={stale || loading} onClick={() => void prepare()}>
          {loading ? 'Reading history…' : 'Build statement'}
        </button>
      )}
      {error && <p role="alert">Statement unavailable · {error}</p>}
      {report && (
        <>
          <p>
            <strong>
              {stale ? 'Stale snapshot' : 'Reconciled'} · blocks {report.coverage.deployment.number}–
              {report.coverage.asOf.number}
            </strong>{' '}
            · Terms revision {report.terms.revision}. Both parties accepted before funding at #
            {report.coverage.fundedAnchor.number}.
          </p>
          <p>
            {report.derived.lifecycle} · {report.derived.q} qualifying seconds · {b(report.derived.earned)}{' '}
            earned · {b(report.derived.claimed)} paid · {b(report.derived.reserved)} reserved ·{' '}
            {b(report.derived.refunded)} refunded · {b(report.derived.refundable)} refundable.
          </p>
          {activation && opening && (
            <p>
              Activated at {String(activation.start)} s for {s.terms.parameters.duration.toString()} s,
              through {String(activation.end)} s. Opening observation{' '}
              {formatUnits(BigInt(String(opening.answer)), Number(s.terms.parameters.referenceDecimals))} at{' '}
              {String(opening.observedAt)} s. Core tick {String(opening.tick)} · fixed band [
              {String(activation.lower)}, {String(activation.upper)}).
            </p>
          )}
          {report.derived.effectiveStop !== '0' && (
            <p>
              Effective stop {report.derived.effectiveStop} s.{' '}
              {report.closeEventEmitted
                ? 'PeriodClosed recorded.'
                : 'Scheduled expiry took effect without a PeriodClosed event.'}
            </p>
          )}
          <button disabled={stale} onClick={download}>
            Download JSON
          </button>
          <h3>Service intervals</h3>
          {!report.intervals.length && <p>No elapsed service interval at this block.</p>}
          {report.intervals.map((i, n) => (
            <p key={n}>
              {i.from}–{i.to} s · {i.kind === 'projected' ? 'Projected from last checkpoint' : 'Persisted'} ·{' '}
              {i.qualified ? 'Qualifying' : i.reasons.join(', ')} · {i.secondsCredited} s credited ·
              cumulative {i.cumulativeQ} s
            </p>
          ))}
          <h3>Token movements</h3>
          {report.movements.map((m, i) => {
            const t = report.tokens.find((t) => t.address === m.token)!
            const fmt = (n: string) => formatUnits(BigInt(n), Number(t.decimals))
            const ev = report.events[Number(m.eventIndex)]
            return (
              <p key={i}>
                #{ev.block} · {m.kind === 'LiquidityExited' ? 'Core removal into vault' : m.kind} ·{' '}
                {m.vaultPrincipalDelta !== undefined
                  ? 'Vault principal ' + fmt(m.vaultPrincipalDelta) + ' / LP fees ' + fmt(m.vaultFeeDelta!)
                  : fmt(m.amount)}{' '}
                {t.symbol}
              </p>
            )
          })}
          <details>
            <summary>Ordered product events ({report.events.length})</summary>
            {report.events.map((e) => (
              <p key={e.block + '-' + e.logIndex}>
                <b>
                  #{e.block} · {e.name}
                </b>{' '}
                · tx {e.transactionIndex}, log {e.logIndex}
                <br />
                <code>{JSON.stringify(e.args)}</code>
                <br />
                <code>{e.transactionHash}</code>
              </p>
            ))}
          </details>
          <h3>Known failed demo receipts</h3>
          {report.knownFailedReceipts.length === 0 && (
            <p>No recorded demo failure in this range. Other failures may be absent from the demo journal.</p>
          )}
          {report.knownFailedReceipts.map((r) => (
            <p key={r.hash}>
              #{r.block} · {r.action} · {r.error}
              <br />
              <code>{r.hash}</code>
            </p>
          ))}
          <p>
            The local node supplies the history and balance reads. A matching result cannot establish that the
            provider supplied every transaction. Download the evidence and its limitations for this block.
          </p>
        </>
      )}
    </section>
  )
}
