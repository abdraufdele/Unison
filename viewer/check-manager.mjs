// Drive only the explicitly identified, isolated funded run prepared by the statement test launcher.
import assert from 'node:assert/strict'
import { zeroHash } from 'viem'

export async function exerciseManager(page, client, target, runId) {
  const headers = { Origin: 'http://127.0.0.1:5173' }
  const status = async () => (await page.request.get(target + '/controls', { headers })).json()
  const initial = await status()
  assert.equal(initial.runId, runId)
  assert.equal(initial.stage, 'funded')
  assert.equal(BigInt(initial.head), (await client.getBlock()).number)
  const csrf = { 'X-Unison-CSRF': initial.csrf, ...headers }
  const url = target + '/controls/action'
  const actionButton = (id) => page.locator('[data-action="' + id + '"]')
  async function step(id) {
    await actionButton(id).click()
    const currentReceipt = page.locator('[data-receipt="' + id + '"]')
    await currentReceipt.waitFor()
    const state = await status(),
      r = state.receipts.at(-1)
    assert.equal(state.stage, id)
    assert.equal(r.success, true)
    assert.ok((await currentReceipt.innerText()).includes(r.hash))
    const block = await client.getBlock({ blockNumber: BigInt(r.block), includeTransactions: true })
    const tx = block.transactions.find((tx) => tx.hash === r.hash)
    assert.equal(tx.from.toLowerCase(), r.sender.toLowerCase())
    assert.equal(tx.to.toLowerCase(), r.target.toLowerCase())
    await page.waitForFunction(
      (n) =>
        document.querySelector('.fresh')?.textContent.includes('Last successful read · Block #' + n + ' ·'),
      state.head
    )
    console.log(id, r.block, r.time, r.hash, r.detail)
    return state
  }
  await page.getByRole('button', { name: 'Use this demo run' }).click()
  assert.equal((await client.getBlock()).number, BigInt(initial.head))
  const body = { runId, version: initial.version, action: 'rerange', positionId: zeroHash }
  const reject = async (data, overrides, code) =>
    assert.equal((await page.request.post(url, { data, headers: { ...csrf, ...overrides } })).status(), code)
  await reject(body, {}, 409) // funded stage
  await step('activate')
  const checkpoint = await step('prepareRange')
  const payload = { ...body, version: checkpoint.version }
  await reject({ ...payload, runId: zeroHash }, {}, 409)
  await reject(payload, { Origin: 'http://localhost:5173' }, 403)
  await reject(payload, { Host: 'localhost:18547' }, 403)
  await reject(payload, { 'X-Unison-CSRF': 'incorrect' }, 403)
  await reject({ ...payload, lower: -240 }, {}, 400)

  // Forward the browser request to the real dispatcher with an obsolete displayed position identity.
  const browserURL = 'http://127.0.0.1:18547/controls/action'
  function deliver(route, body) {
    return route.fetch({
      url,
      headers: { ...route.request().headers(), host: new URL(target).host },
      postData: body,
    })
  }
  await page.route(
    browserURL,
    async (route) => {
      const res = await deliver(route, { ...route.request().postDataJSON(), positionId: zeroHash })
      assert.equal(res.status(), 409)
      await route.fulfill({ response: res })
    },
    { times: 1 }
  )
  await actionButton('rerange').click()
  await page.getByText(/Control request failed.*seed position is stale/).waitFor()
  assert.equal((await status()).head, checkpoint.head)
  assert.equal((await client.getBlock()).number, BigInt(checkpoint.head))

  let duplicates, sent
  await page.route(
    browserURL,
    async (route) => {
      await page.getByText(/Pending · Manager · Extend the position/).waitFor()
      sent = route.request().postDataJSON()
      const responses = await Promise.all([deliver(route, sent), deliver(route, sent)])
      duplicates = responses.map((r) => r.status()).sort()
      await route.fulfill({ response: responses.find((r) => r.ok()) ?? responses[0] })
    },
    { times: 1 }
  )
  await step('rerange')
  assert.deepEqual(duplicates, [200, 409])
  await reject(sent, {}, 409)
  assert.equal((await status()).receipts.filter((r) => r.action === 'rerange').length, 1)
  await step('rangeSwap')
  assert.equal(await page.locator('.qual b').innerText(), 'Qualifying')
  for (const id of ['rangeClose', 'rangeExit', 'rangeWithdraw']) await step(id)
}
