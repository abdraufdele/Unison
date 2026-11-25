import { useCallback, useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { formatUnits } from 'viem'
import { endpoint, type Snapshot } from './read'

const base = new URL('/controls', endpoint).href
type Action = { id: string; label: string; actor: string }
type Receipt = {
  action: string
  label: string
  actor: string
  sender: string
  target: string
  hash: string
  block: number
  time: number
  success: boolean
  detail: string
  error?: string
  revertData?: string
  balances?: { claimed: string; reserved: string; escrowB: string }
}
type Controls = {
  runId: string
  csrf: string
  version: number
  head: number
  stage: string
  actions: Action[]
  receipts: Receipt[]
  problem: string | null
}
const actorName = (actor: string) =>
  ({ treasury: 'Treasury', manager: 'Manager', trader: 'Trader', fixture: 'Mock-token operator' }[actor] ??
  actor)

export function DemoControls({
  s,
  stale,
  refresh,
}: {
  s: Snapshot
  stale: boolean
  refresh: () => Promise<void>
}) {
  const [state, setState] = useState<Controls>()
  const [message, setMessage] = useState('')
  const [enabled, setEnabled] = useState(false)
  const [pending, setPending] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const locked = useRef(false)
  const generation = useRef(0)
  const runId = s.m.runId
  const load = useCallback(async () => {
    const seq = ++generation.current
    try {
      const res = await fetch(base, { cache: 'no-store', signal: AbortSignal.timeout(4000) })
      if (!res.ok) throw Error()
      const next: Controls = await res.json()
      if (next.runId !== runId) throw Error()
      if (seq === generation.current) setState(next)
    } catch {
      if (seq === generation.current) {
        setState(undefined)
        setMessage('Controls unavailable for this run. Refresh reads to reconnect.')
      }
    }
  }, [runId])
  useEffect(() => {
    if (!locked.current && !stale) void load()
    return () => {
      generation.current++
    }
  }, [s.readTime, stale, load])

  const ready = state && !stale && BigInt(state.head) === s.block.number && !pending
  async function submit(action?: Action) {
    if (!state || !ready || !enabled || locked.current || (!action && confirmation !== runId)) return
    locked.current = true
    generation.current++
    setMessage('')
    setPending(action ? actorName(action.actor) + ' · ' + action.label : 'Resetting the named run')
    const body = {
      runId,
      version: state.version,
      ...(action ? { action: action.id } : { confirmation }),
      ...(action?.id === 'rerange' ? { positionId: s.position } : {}),
    }
    try {
      const res = await fetch(base + (action ? '/action' : '/reset'), {
        method: 'POST',
        cache: 'no-store',
        headers: { 'Content-Type': 'application/json', 'X-Unison-CSRF': state.csrf },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(20000),
      })
      const result = await res.json()
      if (!res.ok) throw Error(result.message || 'Refresh the current run and receipts.')
      if (!action) {
        setState(undefined)
        setEnabled(false)
        setConfirmation('')
        setMessage('Reset accepted. Refresh when the new funded run is ready.')
      } else if (result.runId === runId) setState(result)
      else throw Error('Run changed. Refresh reads.')
    } catch (err) {
      setMessage(
        'Control request failed. ' +
          (err instanceof Error ? err.message : 'Check the launcher.') +
          ' Check mined receipts before trying again.'
      )
      setState(undefined)
    } finally {
      locked.current = false
      setPending('')
      await refresh()
    }
  }

  return (
    <section id="demo" className="panel">
      <h2>Local demo actors</h2>
      <p>The launcher operates the mock treasury, manager and trader. No wallet connection is required.</p>
      {!enabled && (
        <button
          disabled={!ready}
          onClick={() => {
            setEnabled(true)
            setMessage('')
          }}
        >
          Use this demo run
        </button>
      )}
      {message && <p role="status">{message}</p>}
      {stale && <p>Controls paused until a fresh agreement snapshot is available.</p>}
      {state?.problem && <p role="alert">{state.problem}</p>}
      {pending && <p role="status">Pending · {pending}</p>}
      {enabled && (
        <div className="actions">
          {state?.actions.map((action) => (
            <button
              key={action.id}
              data-action={action.id}
              disabled={!ready || !!state.problem}
              onClick={() => void submit(action)}
            >
              <small>{actorName(action.actor)}</small>
              {action.label}
            </button>
          ))}
        </div>
      )}
      {!!state?.receipts.length && (
        <div className="receipts">
          <h3>Mined receipts</h3>
          {state.receipts
            .slice()
            .reverse()
            .map((r, i) => (
              <details key={r.hash} open={i === 0} data-receipt={r.action}>
                <summary>
                  {r.success ? 'Mined' : 'Reverted'} · {actorName(r.actor)} · {r.label} · #{r.block}
                </summary>
                <p>
                  {r.error && <strong>{r.error} · </strong>}
                  {r.detail}
                </p>
                {r.balances && (
                  <p>
                    At this block: {formatUnits(BigInt(r.balances.claimed), s.tokenB.decimals)} B paid,{' '}
                    {formatUnits(BigInt(r.balances.reserved), s.tokenB.decimals)} B reserved,{' '}
                    {formatUnits(BigInt(r.balances.escrowB), s.tokenB.decimals)} B in escrow.
                  </p>
                )}
                <code>{r.hash}</code>
                <p>
                  Chain time {r.time} s · From <code>{r.sender}</code> to <code>{r.target}</code>
                </p>
              </details>
            ))}
        </div>
      )}
      {enabled &&
        state &&
        createPortal(
          <details className="panel reset">
            <summary>Disposable run management</summary>
            <p>
              Reset stops this launcher's current chain and starts a new funded agreement. To confirm, enter
              the full current run ID.
            </p>
            <code>{runId}</code>
            <label>
              Current run ID
              <input
                autoComplete="off"
                value={confirmation}
                onChange={(e) => setConfirmation(e.target.value)}
              />
            </label>
            <button disabled={!ready || confirmation !== runId} onClick={() => void submit()}>
              Reset named run
            </button>
          </details>,
          document.getElementById('run-management')!
        )}
    </section>
  )
}
