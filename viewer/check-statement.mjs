import assert from 'node:assert/strict'
import { join } from 'node:path'
import { chromium } from 'playwright-core'
import { createPublicClient, http, parseAbi } from 'viem'

const [port, scenario, runId] = process.argv.slice(2)
assert.match(port, /^\d+$/)
assert.match(runId, /^0x[0-9a-f]{64}$/)
const target = 'http://127.0.0.1:' + port,
  origin = 'http://127.0.0.1:5173'
const client = createPublicClient({ transport: http(target + '/rpc', { retryCount: 0 }), cacheTime: 0 })
const cases = {
  funded: [0, 0, 0, 0, 0, 0],
  active: [1, 333333, 0, 333333, 0, 0],
  terminate: [180, 60000000, 40000000, 20000000, 0, 40000000],
  refund: [180, 60000000, 40000000, 20000000, 40000000, 0],
  repeatRefund: [180, 60000000, 60000000, 0, 40000000, 0],
  swap: [120, 40000000, 0, 40000000, 0, 60000000],
  expiry: [300, 100000000, 0, 100000000, 0, 0],
}
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH, headless: true })
try {
  const page = await browser.newPage()
  page.setDefaultTimeout(14000)
  const errors = [],
    writes = []
  page.on('pageerror', (e) => errors.push(e.message))
  let fault = ''
  await page.route('http://127.0.0.1:18547/**', async (route) => {
    const req = route.request(),
      url = new URL(req.url()),
      path = url.pathname
    if (path.startsWith('/controls/') && req.method() === 'POST') writes.push(path)
    if (fault === 'rpc' && path.startsWith('/statement/')) return route.abort()
    const response = await route.fetch({
      url: target + path,
      headers: { ...req.headers(), host: '127.0.0.1:' + port },
    })
    if (fault && path.startsWith('/statement/') && response.ok()) {
      const data = await response.json()
      if (fault === 'schema') data.schema = 'unknown'
      if (fault === 'build') data.buildId = 'unknown'
      if (fault === 'mismatch') data.derived.earned = (BigInt(data.derived.earned) + 1n).toString()
      if (fault === 'run') data.runId = '0x' + 'aa'.repeat(32)
      return route.fulfill({ json: data })
    }
    return route.fulfill({ response })
  })
  const before = await client.getBlock()
  await page.goto(origin)
  const section = page.locator('#statement'),
    build = section.getByRole('button', { name: 'Build statement' })
  await build.click()
  await section.getByText(/Reconciled · blocks|Statement unavailable/).waitFor()
  assert.ok(!(await section.getByRole('alert').count()), await section.innerText())
  const download = section.getByRole('button', { name: 'Download JSON' })
  const ready = page.waitForEvent('download')
  await download.click()
  const file = await ready
  const stream = await file.createReadStream()
  const parts = []
  for await (const part of stream) parts.push(part)
  if (process.env.STATEMENT_DOWNLOAD_DIR)
    await file.saveAs(join(process.env.STATEMENT_DOWNLOAD_DIR, file.suggestedFilename()))
  const raw = Buffer.concat(parts).toString(),
    r = JSON.parse(raw)
  assert.equal(r.runId, runId)
  assert.ok(file.suggestedFilename().includes(runId + '-' + before.number))
  assert.doesNotMatch(raw, /csrf|mnemonic|private.?key/i)
  assert.equal(r.coverage.asOf.hash, before.hash)
  assert.match(
    await page.locator('.fresh').innerText(),
    new RegExp('Block #' + r.coverage.asOf.number + ' ·')
  )
  assert.deepEqual(
    ['q', 'earned', 'claimed', 'reserved', 'refunded', 'refundable'].map((k) => r.derived[k]),
    cases[scenario].map(String)
  )
  assert.deepEqual(r.derived, r.contractReads)
  assert.ok(BigInt(r.coverage.deployment.number) < BigInt(r.coverage.fundedAnchor.number))
  assert.equal(r.events.filter((e) => e.name === 'PartyAccepted').length, 2)
  const ids = r.events.map((e) => [e.block, e.transactionIndex, e.logIndex].map(BigInt))
  for (let i = 1; i < ids.length; i++)
    assert.ok(ids[i][0] > ids[i - 1][0] || (ids[i][0] === ids[i - 1][0] && ids[i][2] > ids[i - 1][2]))
  const abi = parseAbi([
    'function balanceOf(address) view returns (uint256)',
    'function projectedSeconds() view returns (uint256)',
    ...['earned', 'claimed', 'reserved', 'refunded', 'refundable'].map(
      (n) => 'function ' + n + '() view returns (uint256)'
    ),
  ])
  const read = (address, functionName, args) =>
    client.readContract({ abi, address, functionName, args, blockNumber: before.number })
  assert.equal(String(await read(r.addresses.hook, 'projectedSeconds')), r.derived.q)
  for (const k of ['earned', 'claimed', 'reserved', 'refunded', 'refundable'])
    assert.equal(String(await read(r.addresses.escrow, k)), r.derived[k])
  assert.equal(String(await read(r.addresses.tokenB, 'balanceOf', [r.addresses.escrow])), r.derived.escrowB)
  if (scenario === 'active') assert.equal(r.intervals.at(-1).kind, 'projected')
  if (scenario === 'expiry') {
    assert.equal(r.derived.lifecycle, 'Expired')
    assert.equal(r.closeEventEmitted, false)
    assert.equal(r.derived.persistedQ, '0')
    assert.equal(r.intervals.at(-1).to, r.derived.effectiveStop)
    assert.match(await section.innerText(), /without a PeriodClosed event/)
  }
  if (scenario === 'swap') {
    const gap = r.intervals.find((i) => !i.qualified)
    assert.equal(BigInt(gap.to) - BigInt(gap.from), 120n)
    assert.ok(gap.reasons.includes('tick outside position'))
  }
  if (scenario === 'repeatRefund') {
    assert.deepEqual(
      r.knownFailedReceipts.map((f) => f.error),
      ['TransferFailed(address)', 'InvalidPeriod()']
    )
    assert.deepEqual(
      r.movements.filter((m) => m.kind === 'Treasury withdrawal').map((m) => m.amount),
      ['2100346049', '1900054977']
    )
    assert.deepEqual(
      r.movements.filter((m) => m.kind === 'LiquidityExited').map((m) => m.vaultFeeDelta),
      ['301038', '0']
    )
    const url = target + '/statement/' + runId + '/' + before.number + '/' + before.hash
    const wrong = await page.request.get(url.replace(runId, '0x' + 'ff'.repeat(32)))
    assert.equal(wrong.status(), 409)
    for (const f of ['schema', 'build', 'run', 'mismatch', 'rpc']) {
      fault = f
      await page.reload()
      await build.click()
      await section.getByRole('alert').waitFor()
      assert.equal(await download.count(), 0)
    }
  }
  assert.equal((await client.getBlock()).hash, before.hash)
  assert.deepEqual(writes, [])
  assert.deepEqual(errors, [])
  console.log(
    scenario,
    'exported blocks',
    r.coverage.deployment.number + '–' + r.coverage.asOf.number,
    'events',
    r.events.length,
    'Q',
    r.derived.q,
    'earned',
    r.derived.earned,
    'known failures',
    r.knownFailedReceipts.length
  )
} finally {
  await browser.close()
}
