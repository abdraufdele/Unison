// Read-only browser verification. The operator creates each state at the owned demo prompt.
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { chromium } from 'playwright-core'

const expected = {
  funded: ['Funded', '0 B', '0 B', '0 B', '0', '0', '0', '2000', '2000'],
  active: [
    'Active',
    '0.333333 B',
    '0.333333 B',
    '0 B',
    '1',
    '0',
    '100,000,000,000',
    '1401.826223',
    '1401.826223',
  ],
  interrupted: [
    'Active',
    '30 B',
    '30 B',
    '0 B',
    '90',
    '120',
    '100,000,000,000',
    '1401.826223',
    '1401.826223',
  ],
  terminal: [
    'Terminated',
    '30 B',
    '30 B',
    '70 B',
    '90',
    '120',
    '100,000,000,000',
    '1401.826223',
    '1401.826223',
  ],
}
const phase = process.argv[2]
if (!(phase in expected) && !['faults', 'old-manifest'].includes(phase))
  throw Error('Specify a fixture stage, faults, or old-manifest <file>.')
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH, headless: true })
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 960 } })
  const errors = [],
    calls = []
  page.on('pageerror', (e) => errors.push(e.message))
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text())
  })
  page.on('request', (r) => {
    if (!r.url().endsWith('/rpc') || r.method() !== 'POST') return
    const body = r.postDataJSON()
    calls.push(...(Array.isArray(body) ? body : [body]))
  })
  const url = 'http://127.0.0.1:5173/'
  const manifestUrl = 'http://127.0.0.1:18547/deployment.json'
  const rpc = 'http://127.0.0.1:18547/rpc'
  const textMatch = (name) => new RegExp('^' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '$')
  const field = (name) =>
    page
      .getByRole('term')
      .filter({ hasText: textMatch(name) })
      .locator('..')
      .locator('dd')
  const value = async (name) => (await field(name).innerText()).trim()
  const wait = (locator) => locator.waitFor({ timeout: 12000 })
  const alert = async (name) => wait(page.getByRole('alert').getByText(name, { exact: true }))
  if (phase === 'old-manifest') {
    const stale = JSON.parse(await readFile(process.argv[3], 'utf8'))
    const current = await (await page.request.get(manifestUrl)).json()
    assert.notEqual(stale.runId, current.runId)
    assert.equal(stale.chainId, current.chainId)
    await page.route(manifestUrl, (route) => route.fulfill({ json: stale }))
    await page.goto(url)
    await alert('Stale deployment manifest')
    assert.equal(await page.locator('#settlement').count(), 0)
    console.log('Rejected the previous manifest on the same chain ID.')
  } else {
    await page.goto(url)
    await wait(page.locator('#settlement'))
    const block = (await page.locator('.fresh').innerText()).match(/Block #(\d+)/)[1]
    const reads = calls.filter((c) => ['eth_call', 'eth_getCode'].includes(c.method))
    assert.ok(reads.length >= 35)
    assert.ok(
      reads.every((c) => BigInt(c.params[1]) === BigInt(block)),
      'read mixed blocks'
    )
    assert.ok(
      calls.every((c) =>
        ['eth_chainId', 'eth_getBlockByNumber', 'eth_call', 'eth_getCode'].includes(c.method)
      )
    )
    assert.deepEqual(errors, [])
    if (phase in expected) {
      const [life, earned, reserve, refund, seconds, tick, l, va, vb] = expected[phase]
      for (const [key, actual] of Object.entries({
        Lifecycle: life,
        'Terms revision': '1',
        'Accepted revision · treasury / manager': '1 / 1',
        'Original duration': '300 s',
        'Effective stop': phase === 'terminal' ? '2180 s' : 'Unset',
        'Opening band': phase === 'funded' ? 'Set at activation' : '[-120, 120)',
        Earned: earned,
        'Claimable now': reserve,
        'Unpaid earned reserve': reserve,
        'Refundable now': refund,
        'Current core tick': tick,
        'Owned liquidity (L)': l,
        'Funded budget': '100 B',
        Claimed: '0 B',
        Refunded: '0 B',
      }))
        assert.equal(await value(key), actual, key)
      assert.equal(await page.locator('.time strong').innerText(), seconds)
      assert.match(
        await page.locator('.clockfoot').innerText(),
        new RegExp((phase === 'funded' || phase === 'active' ? '0' : '90') + ' s persisted')
      )
      assert.equal(
        await page.locator('.qual b').innerText(),
        phase === 'active' ? 'Qualifying' : 'Not qualifying'
      )
      if (phase === 'interrupted')
        assert.match(await page.locator('.qual').innerText(), /Tick outside position/)
      assert.deepEqual(await page.locator('tbody td').allTextContents(), [va, vb, '0', '100'])
      assert.equal(await value('Agreement ID'), await value('Run ID'))
      console.log(
        phase,
        'block',
        block,
        life,
        earned,
        'earned,',
        refund,
        'refundable;',
        reads.length,
        'block-pinned reads'
      )
      if (process.env.SCREENSHOT) await page.screenshot({ path: process.env.SCREENSHOT })
      await page.setViewportSize({ width: 390, height: 844 })
      assert.ok(
        await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
        'mobile overflow'
      )
    } else {
      const refresh = () => page.getByRole('button', { name: 'Refresh reads' }).click()
      await page.route(rpc, (route) => route.abort())
      await refresh()
      await alert('Local RPC disconnected')
      assert.match(await page.locator('.fresh').innerText(), /Stale snapshot/)
      assert.equal(await page.locator('#settlement').count(), 1)
      await page.unroute(rpc)
      async function corrupt(method, reply, title) {
        await page.route(rpc, async (route) => {
          const request = route.request().postDataJSON()
          const reqs = Array.isArray(request) ? request : [request]
          const original = await route.fetch()
          const body = await original.json()
          const replies = (Array.isArray(body) ? body : [body]).map((item) =>
            reqs.find((r) => r.id === item.id)?.method === method
              ? { jsonrpc: '2.0', id: item.id, ...reply }
              : item
          )
          await route.fulfill({ json: Array.isArray(body) ? replies : replies[0] })
        })
        await refresh()
        await alert(title)
        await page.unroute(rpc)
      }
      await corrupt(
        'eth_call',
        { error: { code: -32000, message: 'fixture unavailable' } },
        'Contract read failed'
      )
      assert.match(await page.locator('.fresh').innerText(), /Stale snapshot/)
      await corrupt('eth_chainId', { result: '0x1' }, 'Wrong chain')
      assert.equal(await page.locator('#settlement').count(), 0)
      await corrupt('eth_getCode', { result: '0x' }, 'Missing contract code')
      const manifest = await (await page.request.get(manifestUrl)).json()
      await page.route(manifestUrl, (route) =>
        route.fulfill({ json: { ...manifest, runId: '0x' + '55'.repeat(32) } })
      )
      await refresh()
      await alert('Wrong deployment identity')
      await page.unroute(manifestUrl)
      await page.route(manifestUrl, (route) => route.fulfill({ status: 404, body: '' }))
      await refresh()
      await alert('Deployment manifest unavailable')
      assert.equal(await page.locator('#settlement').count(), 0)
      console.log(
        'Retained stale snapshot on transport/read failure; blocked wrong chain, missing code, wrong marker and missing manifest.'
      )
    }
  }
} finally {
  await browser.close()
}
