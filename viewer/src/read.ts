import {
  createPublicClient,
  getContract,
  http,
  isAddress,
  isHash,
  keccak256,
  type Address,
  type Hash,
} from 'viem'
import * as abi from './contracts'

export const endpoint = 'http://127.0.0.1:18547/rpc'
const roles = ['vault', 'escrow', 'hook', 'core', 'tokenA', 'tokenB', 'lens', 'adapter'] as const
type Role = (typeof roles)[number]
export type Manifest = {
  schema: 1
  chainId: number
  endpoint: string
  runId: Hash
  buildId: string
  anchor: { number: string; hash: Hash }
  addresses: Record<Role, Address>
  codeHashes: Record<Role, Hash>
}

export class ReadIssue extends Error {
  constructor(readonly title: string, detail: string, readonly discard = false) {
    super(detail)
  }
}

const stale = () =>
  new ReadIssue('Stale deployment manifest', 'Reload the manifest from the current local demo run.', true)
const mismatch = () =>
  new ReadIssue(
    'Wrong deployment identity',
    'The onchain agreement or its bindings differ from this run. Refresh after checking the local setup.',
    true
  )
const offline = () =>
  new ReadIssue('Local RPC disconnected', 'Start or reconnect the disposable demo, then refresh.')

export async function deployment(): Promise<Manifest> {
  let res: Response
  try {
    res = await fetch('http://127.0.0.1:18547/deployment.json', {
      cache: 'no-store',
      signal: AbortSignal.timeout(4000),
    })
  } catch {
    throw offline()
  }
  if (!res.ok)
    throw new ReadIssue(
      'Deployment manifest unavailable',
      'Start the local fixture and wait for its Ready message.',
      true
    )
  let m
  try {
    m = await res.json()
  } catch {
    throw stale()
  }
  if (
    !m ||
    typeof m !== 'object' ||
    m.schema !== 1 ||
    m.buildId !== abi.buildId ||
    m.chainId !== 31337 ||
    m.endpoint !== endpoint ||
    !isHash(typeof m.runId === 'string' ? m.runId : '') ||
    !isHash(typeof m.anchor?.hash === 'string' ? m.anchor.hash : '') ||
    !/^\d{1,20}$/.test(m.anchor?.number ?? '') ||
    roles.some((k) => !isAddress(m.addresses?.[k] ?? '') || !isHash(m.codeHashes?.[k] ?? ''))
  )
    throw stale()
  return m
}

const client = createPublicClient({
  ccipRead: false,
  cacheTime: 0,
  transport: http(endpoint, {
    retryCount: 0,
    timeout: 5000,
    batch: { batchSize: 64, wait: 1 },
  }),
})
const same = (a: Address, b: Address) => a.toLowerCase() === b.toLowerCase()

export async function snapshot(m: Manifest) {
  let chainId
  try {
    chainId = await client.getChainId()
  } catch {
    throw offline()
  }
  if (chainId !== m.chainId)
    throw new ReadIssue('Wrong chain', 'Connect the local reader to its owned Anvil chain (31337).', true)
  const block = await client.getBlock()
  if (block.number < BigInt(m.anchor.number)) throw stale()
  const anchor = await client.getBlock({ blockNumber: BigInt(m.anchor.number) })
  if (anchor.hash !== m.anchor.hash) throw stale()
  const at = { blockNumber: block.number }
  const a = m.addresses
  await Promise.all(
    roles.map(async (role) => {
      const code = await client.getCode({ address: a[role], ...at })
      if (!code || code === '0x')
        throw new ReadIssue(
          'Missing contract code',
          'The ' + role + ' address has no code at this block. Check the deployment manifest.',
          true
        )
      if (keccak256(code) !== m.codeHashes[role]) throw mismatch()
    })
  )

  const v = getContract({ address: a.vault, abi: abi.AgreementVault, client }).read
  const e = getContract({ address: a.escrow, abi: abi.CompensationEscrow, client }).read
  const h = getContract({ address: a.hook, abi: abi.ServiceHook, client }).read
  const lens = getContract({ address: a.lens, abi: abi.ComparisonRouter, client }).read
  const [
    id,
    terms,
    hash,
    phase,
    start,
    end,
    stop,
    consentT,
    consentM,
    lo,
    hi,
    pl,
    pu,
    salt,
    position,
    poolId,
    qualification,
    persisted,
    projected,
    hv,
    ev,
    payToken,
    payTreasury,
    payManager,
  ] = await Promise.all([
    v.agreementId(at),
    v.currentTerms(at),
    v.termsHash(at),
    v.state(at),
    v.start(at),
    v.scheduledEnd(at),
    v.effectiveStop(at),
    v.treasuryAcceptedRevision(at),
    v.managerAcceptedRevision(at),
    v.bandLower(at),
    v.bandUpper(at),
    v.positionLower(at),
    v.positionUpper(at),
    v.positionSalt(at),
    v.positionId(at),
    h.poolId(at),
    h.qualification(at),
    h.qualifyingSeconds(at),
    h.projectedSeconds(at),
    h.vault(at),
    e.vault(at),
    e.paymentToken(at),
    e.treasuryRecipient(at),
    e.managerRecipient(at),
  ])
  const b = terms.bindings
  if (
    id !== m.runId ||
    terms.agreementId !== id ||
    terms.chainId !== BigInt(m.chainId) ||
    !same(terms.vault, a.vault) ||
    !same(hv, a.vault) ||
    !same(ev, a.vault) ||
    !same(payToken, a.tokenB) ||
    !same(b.poolManager, a.core) ||
    !same(b.hook, a.hook) ||
    !same(b.escrow, a.escrow) ||
    !same(b.referenceAdapter, a.adapter) ||
    !same(b.token0, a.tokenA) ||
    !same(b.token1, a.tokenB) ||
    !same(payTreasury, terms.treasuryRecipient) ||
    !same(payManager, terms.managerRecipient)
  )
    throw mismatch()

  async function token(address: Address) {
    const t = getContract({ address, abi: abi.CustodyToken, client }).read
    const [decimals, vault, escrow] = await Promise.all([
      t.decimals(at),
      t.balanceOf([a.vault], at),
      t.balanceOf([a.escrow], at),
    ])
    return { decimals, vault, escrow }
  }
  const key = {
    currency0: a.tokenA,
    currency1: a.tokenB,
    fee: terms.parameters.fee,
    tickSpacing: terms.parameters.tickSpacing,
    hooks: a.hook,
  }
  const [core, tokenA, tokenB, funded, earned, claimed, reserved, claimable, refunded, refundable] =
    await Promise.all([
      lens.position([key, a.vault, pl, pu, salt], at),
      token(a.tokenA),
      token(a.tokenB),
      e.fundedBudget(at),
      e.earned(at),
      e.claimed(at),
      e.reserved(at),
      e.claimable(at),
      e.refunded(at),
      e.refundable(at),
    ])
  // Catch a reset/reorg between the component reads before publishing the snapshot.
  if ((await client.getBlock(at)).hash !== block.hash) throw stale()
  return {
    m,
    block,
    terms,
    hash,
    phase,
    start,
    end,
    stop,
    consentT,
    consentM,
    lo,
    hi,
    pl,
    pu,
    salt,
    position,
    poolId,
    qualification,
    persisted,
    projected,
    core,
    tokenA,
    tokenB,
    funded,
    earned,
    claimed,
    reserved,
    claimable,
    refunded,
    refundable,
    readTime: new Date(),
  }
}
export type Snapshot = Awaited<ReturnType<typeof snapshot>>
