// Changes and resets only the explicitly named funded demo. Use the run ID printed by the launcher.
import assert from 'node:assert/strict'
import { chromium } from 'playwright-core'
import { createPublicClient, formatUnits, http, parseAbi, toFunctionSelector } from 'viem'

const origin = 'http://127.0.0.1:5173'
const base = 'http://127.0.0.1:18547'
const manifestUrl = base + '/deployment.json'
const actionUrl = base + '/controls/action'
const resetUrl = base + '/controls/reset'
const confirmedRun = process.argv[2]
assert.match(
  confirmedRun ?? '',
  /^0x[0-9a-f]{64}$/,
  'Pass the full funded run ID to authorize this replay and reset.'
)
const rpc = createPublicClient({ transport: http(base + '/rpc', { retryCount: 0 }) })
const abi = parseAbi([
  ...['earned', 'claimed', 'reserved', 'refundable', 'refunded', 'projectedSeconds'].map(
    (name) => 'function ' + name + '() view returns (uint256)'
  ),
  'function balanceOf(address) view returns (uint256)',
  'function treasuryRecipient() view returns (address)',
  'function managerRecipient() view returns (address)',
])
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH, headless: true })
let diagnose
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } })
  page.setDefaultTimeout(15000)
  const errors = [],
    writes = []
  page.on('pageerror', (e) => errors.push(e.message))
  page.on('request', (r) => {
    if (r.method() === 'POST' && r.url().includes('/controls/')) writes.push(r.url())
  })
  const manifest = async () => (await page.request.get(manifestUrl)).json()
  const status = async () =>
    (await page.request.get(base + '/controls', { headers: { Origin: origin } })).json()
  let action = 'verify funded run'
  const transportErrors = []
  page.on('requestfailed', (request) => {
    transportErrors.push([new URL(request.url()).pathname, request.failure()?.errorText])
  })
  diagnose = async () => {
    // Include only the public stage and receipt. Control headers and tokens stay out of diagnostics.
    const current = await status().catch(() => undefined)
    const last = current?.receipts.at(-1)
    console.error('Journey diagnostic', {
      action,
      expectedRun: confirmedRun,
      observedRun: current?.runId,
      stage: current?.stage,
      head: current?.head,
      lastReceipt: last && [last.action, last.block, last.hash, last.success],
      problem: current?.problem,
      pageErrors: errors,
      transportErrors: transportErrors.slice(-5),
      freshness: await page
        .locator('.fresh')
        .textContent({ timeout: 1000 })
        .catch(() => undefined),
    })
  }
  const post = (url, data, token, headers = {}) =>
    page.request.post(url, { data, headers: { Origin: origin, 'X-Unison-CSRF': token, ...headers } })
  const field = (name) =>
    page
      .getByRole('term', { name: '', exact: true })
      .filter({ hasText: new RegExp('^' + name + '$') })
      .locator('..')
      .locator('dd')
  const verifyBlock = async (n) =>
    page.waitForFunction(
      (n) =>
        document.querySelector('.fresh')?.textContent.includes('Last successful read · Block #' + n + ' ·'),
      n
    )
  let m = await manifest(),
    start = await status()
  assert.equal(m.runId, confirmedRun)
  assert.equal(start.stage, 'funded')
  assert.equal(start.runId, m.runId)
  const initial = { action: 'activate', runId: m.runId, version: start.version }
  const headers = start.csrf
  for (const [payload, token, extra, code] of [
    [initial, headers, { Origin: 'http://localhost:5173' }, 403],
    [initial, headers, { Origin: '' }, 403],
    [initial, headers, { Host: 'localhost:18547' }, 403],
    [initial, 'wrong', {}, 403],
    [{ ...initial, runId: 'stale' }, headers, {}, 409],
    [{ ...initial, action: 'claim20' }, headers, {}, 409],
    [{ ...initial, action: 'evm_mine' }, headers, {}, 409],
    [{ ...initial, to: m.addresses.vault }, headers, {}, 400],
  ])
    assert.equal((await post(actionUrl, payload, token, extra)).status(), code)
  assert.equal(
    (await post(resetUrl, { runId: m.runId, version: 0, confirmation: 'RESET' }, headers)).status(),
    409
  )
  for (const method of [
    'eth_sendTransaction',
    'eth_accounts',
    'evm_setNextBlockTimestamp',
    'anvil_setStorageAt',
  ]) {
    const result = await page.request.post(base + '/rpc', {
      data: { id: 1, jsonrpc: '2.0', method, params: [] },
    })
    assert.equal((await result.json()).error.code, -32601)
  }
  await page.goto(origin)
  await verifyBlock(start.head)
  await page.getByRole('button', { name: 'Refresh reads' }).click()
  await page.getByRole('button', { name: 'Use this demo run' }).click()
  assert.deepEqual(writes, [])
  assert.equal((await rpc.getBlock()).number, BigInt(start.head))

  // Drop the outbound action before delivery. No receipt or optimistic activation may appear.
  await page.route(actionUrl, (route) => route.abort())
  await page.locator('[data-action="activate"]').click()
  await page.getByText(/Control request failed/).waitFor()
  assert.equal((await status()).version, 0)
  assert.equal((await rpc.getBlock()).number, BigInt(start.head))
  await page.unroute(actionUrl)
  await page.getByRole('button', { name: 'Refresh reads' }).click()

  // Deliver the browser's identical activation twice concurrently; only one can be broadcast.
  let duplicates
  await page.route(
    actionUrl,
    async (route) => {
      await page.getByText('Pending · Treasury · Activate the agreement', { exact: true }).waitFor()
      const requests = await Promise.all([route.fetch(), route.fetch()])
      duplicates = requests.map((r) => r.status()).sort()
      await route.fulfill({ response: requests.find((r) => r.ok()) ?? requests[0] })
    },
    { times: 1 }
  )

  async function step(id) {
    action = id
    await page.locator('[data-action="' + id + '"]').click()
    const item = page.locator('[data-receipt="' + id + '"]')
    try {
      await item.waitFor()
    } catch (e) {
      console.error(id, await page.locator('#demo').innerText())
      throw e
    }
    const current = await status()
    assert.equal(current.stage, id)
    const r = current.receipts.at(-1)
    assert.equal(r.action, id)
    assert.match(await item.innerText(), new RegExp(r.hash))
    await verifyBlock(current.head)
    // The public reader serves the mined block and transaction independently of controller history.
    const mined = await rpc.getBlock({ blockNumber: BigInt(r.block), includeTransactions: true })
    const tx = mined.transactions.find((tx) => tx.hash === r.hash)
    assert.ok(tx)
    assert.equal(tx.from.toLowerCase(), r.sender.toLowerCase())
    assert.equal(tx.to.toLowerCase(), r.target.toLowerCase())
    assert.equal(mined.timestamp, BigInt(r.time))
    const read = (address, functionName, args) =>
      rpc.readContract({ address, abi, functionName, args, blockNumber: mined.number })
    const a = m.addresses
    const owner = await read(a.escrow, 'treasuryRecipient'),
      manager = await read(a.escrow, 'managerRecipient')
    const values = {}
    for (const name of ['earned', 'claimed', 'reserved', 'refunded', 'refundable'])
      values[name] = await read(a.escrow, name)
    const q = await read(a.hook, 'projectedSeconds')
    const balance = (token, who) => read(token, 'balanceOf', [who])
    const [managerB, escrowB, treasuryA, treasuryB, vaultA, vaultB] = await Promise.all([
      balance(a.tokenB, manager),
      balance(a.tokenB, a.escrow),
      balance(a.tokenA, owner),
      balance(a.tokenB, owner),
      balance(a.tokenA, a.vault),
      balance(a.tokenB, a.vault),
    ])
    assert.equal(managerB, values.claimed)
    assert.equal(values.earned - values.claimed, values.reserved)
    assert.equal(escrowB + values.claimed + values.refunded, 100_000_000n)
    for (const [key, label] of Object.entries({
      earned: 'Earned',
      claimed: 'Claimed',
      reserved: 'Unpaid earned reserve',
      refunded: 'Refunded',
      refundable: 'Refundable now',
    })) {
      // Activation includes an explicit +1 s observation block for the read-only viewer.
      if (id !== 'activate') assert.equal(await field(label).innerText(), formatUnits(values[key], 6) + ' B')
    }
    assert.deepEqual(
      await page.locator('tbody td').allTextContents(),
      [vaultA, vaultB, 0n, escrowB].map((x) => formatUnits(x, 6))
    )
    if (id !== 'activate') assert.equal(await page.locator('.time strong').innerText(), q.toString())
    assert.equal(r.success, !['failedClaim', 'revoked'].includes(id))
    console.log([id, r.block, r.time, r.hash, r.success ? 'mined' : 'reverted', r.detail].join(' | '))
    return { r, q, ...values, escrowB, managerB, treasuryA, treasuryB, vaultA, vaultB }
  }

  console.log('Payment-failure run', m.runId)
  await step('activate')
  assert.deepEqual(duplicates, [200, 409])
  assert.equal((await post(actionUrl, initial, headers)).status(), 409)
  assert.equal((await status()).receipts.length, 1)
  assert.equal((await step('trade')).q, 120n)
  assert.equal((await step('claim40')).managerB, 40_000_000n)
  assert.equal((await step('checkpoint')).q, 180n)
  const independentRights = ({ r, ...values }) => values
  const blocked = await step('block'),
    failed = await step('failedClaim')
  assert.equal(
    failed.r.revertData,
    toFunctionSelector('TransferFailed(address)') +
      m.addresses.tokenB.slice(2).toLowerCase().padStart(64, '0')
  )
  assert.deepEqual(independentRights(failed), independentRights(blocked))
  const close = await step('terminate')
  assert.deepEqual(
    [close.q, close.earned, close.claimed, close.reserved, close.refundable, close.escrowB],
    [180n, 60_000_000n, 40_000_000n, 20_000_000n, 40_000_000n, 60_000_000n]
  )
  const revoked = await step('revoked')
  assert.equal(revoked.r.revertData, toFunctionSelector('InvalidPeriod()'))
  assert.deepEqual(independentRights(revoked), independentRights(close))
  const removed = await step('remove'),
    withdrawal = await step('withdraw')
  assert.equal(await field('Owned liquidity \\(L\\)').innerText(), '0')
  assert.deepEqual(
    [withdrawal.treasuryA - removed.treasuryA, withdrawal.treasuryB - removed.treasuryB],
    [removed.vaultA, removed.vaultB]
  )
  assert.ok(removed.vaultA > 0n && removed.vaultB > 0n)
  assert.equal(withdrawal.escrowB, 60_000_000n)
  const refund = await step('refund')
  assert.equal(refund.treasuryB - withdrawal.treasuryB, 40_000_000n)
  assert.equal(refund.escrowB, 20_000_000n)
  await step('restore')
  const paid = await step('claim20')
  assert.equal(paid.managerB - refund.managerB, 20_000_000n)
  const repeat = await step('repeatClaim'),
    end = await step('repeatRefund')
  assert.deepEqual(independentRights(end), independentRights(repeat))
  assert.deepEqual(independentRights(repeat), independentRights(paid))
  assert.equal(end.escrowB, 0n)
  await page.setViewportSize({ width: 390, height: 844 })
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
  action = 'verify named reset and replacement identity'
  const old = m
  await page.getByText('Disposable run management', { exact: true }).click()
  await page.getByLabel('Current run ID').fill(confirmedRun)
  await page.getByRole('button', { name: 'Reset named run' }).click()
  // Wait for the page itself to read the replacement deployment and clear the old actor selection.
  await page.waitForFunction(
    (previous) => {
      const label = [...document.querySelectorAll('dt')].find((el) => el.textContent === 'Run ID')
      const id = label?.nextElementSibling?.textContent
      return /^0x[0-9a-f]{64}$/.test(id ?? '') && id !== previous
    },
    confirmedRun,
    { timeout: 45000 }
  )
  await page.getByRole('button', { name: 'Use this demo run' }).waitFor()
  // Require a real new identity even though both deployments use the same chain and funded height.
  m = await manifest()
  assert.notEqual(old.runId, m.runId)
  assert.notEqual(old.anchor.hash, m.anchor.hash)
  const fresh = await status()
  assert.equal(fresh.stage, 'funded')
  assert.equal((await post(actionUrl, initial, headers)).status(), 403)
  assert.equal((await post(actionUrl, initial, fresh.csrf)).status(), 409)
  assert.equal((await status()).version, 0)
  await page.route(manifestUrl, (route) => route.fulfill({ json: old }))
  await page.reload()
  await page.getByRole('alert').getByText('Stale deployment manifest', { exact: true }).waitFor()
  assert.equal(await page.locator('#demo').count(), 0)
  await page.unroute(manifestUrl)
  await page.reload()
  await page.getByRole('button', { name: 'Use this demo run' }).click()
  console.log('Separate interruption run', m.runId)
  await step('activate')
  assert.equal((await step('interrupt')).q, 90n)
  assert.match(await page.locator('.qual').innerText(), /Tick outside position/)
  assert.equal((await step('return')).q, 90n)
  assert.equal(await page.locator('.qual b').innerText(), 'Qualifying')
  assert.equal((await step('returnClose')).q, 120n)
  assert.deepEqual(errors, [])
  console.log(
    'Browser journeys, receipt identities, independent balances, duplicate/stale requests and read-only checks passed.'
  )
} catch (error) {
  await diagnose?.()
  throw error
} finally {
  await browser.close()
}
