# Pitch and demo script

**One sentence.** Unison lets a treasury hire a manager for one v4 position and pay from a separate budget for the seconds that position delivers the agreed liquidity.

**30-second pitch.** What should a treasury pay when its manager’s position qualifies for only part of the contract? Unison’s hook observes swaps, its vault bounds the manager’s actions, and its escrow pays for qualifying time. In our local run, 180 of 300 seconds earned 60 B. Even with payment blocked, the treasury recovered its assets and the manager kept a claim on unpaid earnings. A matched retainer delivered equal liquidity. What changes is how the bill gets settled.

## Spoken demo

Use the built loopback preview on the [pinned setup](../README.md#setup). Start at the funded page in a fresh **payment run**. Open the [author receipt table](A6-AUTHOR-REHEARSAL.md#run-identities-and-receipts) and [M6 comparison](M6-COMPARISON.md) in two other tabs. The last two segments use published local evidence, so the audience can inspect distinct runs without waiting for resets. The pitch above stands alone. Start the video with the first line below.

### 0:00–0:35 · What the treasury bought (35 seconds)

**Screen and action.** Show the run ID in **Pool and deployment**. On funded block 22 select **Build statement**. Expand **Ordered product events** to show the acceptances and funding. Select **Use this demo run**, then **Activate the agreement**. Allow each receipt to mine before the next action.

> This treasury has hired one manager for one position in a fixed-fee pool. Here are their two acceptances. The vault holds two thousand of each token. The hundred B for pay lives in a separate escrow. These are six-decimal mock tokens on local Anvil. The controls use local actors and advance chain time between real transactions. Activation fixes the opening band for three hundred seconds.

**Expected evidence.** Funding credits at block 22, activation receipt at 23, opening band [−120, 120). The empty observation block at 24 shows a projected second. [Funded and active statements](LOCAL-VIEWER.md#checked-browser-downloads)

### 0:35–1:15 · Read the invoice before the failure (40 seconds)

**Screen and action.** Select **Trade inside the range at +120 s**, **Claim the first 40 B**, then **Checkpoint service at +180 s**. Hold on the clock and escrow amounts.

> A second counts while this vault’s position covers the opening band, holds the agreed minimum liquidity, and contains the tick actually stored by the pool. The hook observes the swap, credits the previous interval and reads the new state. An untouched qualifying position earns too. At one hundred twenty seconds the manager pulls forty B. At one hundred eighty seconds the invoice is sixty B. Forty has already moved, so twenty is still owed.

**Expected evidence.** Blocks 25–27 show Q=120, an actual 40 B receipt, then Q=180. At block 27, 100 × 180/300 = 60 B earned, 20 B reserved. [Payment receipts](LOCAL-VIEWER.md#run-the-payment-failure-journey)

### 1:15–1:55 · Fail a payment and revoke authority (40 seconds)

**Screen and action.** Select **Block the escrow-to-manager route**, **Attempt the remaining 20 B claim**, **Terminate with payment blocked**, then **Attempt a revoked liquidity removal**. Expand both failed entries under **Mined receipts**.

> We block just the escrow’s transfer to the manager. Here is the mined claim that reverted. The treasury can still terminate. That freezes the clock at one hundred eighty seconds and revokes the manager’s authority. This same bounded removal passed simulation while the agreement was active. Now the manager actually sends it. The vault rejects it. The two receipts tell us which right failed to transfer and which authority has ended.

**Expected evidence.** Block 29 has status zero and `TransferFailed(address)`. Block 30 freezes rights. Block 31 has status zero and `InvalidPeriod()`. The two failures preserve balances. [Receipt details and active simulation](LOCAL-VIEWER.md#run-the-payment-failure-journey)

### 1:55–2:32 · Follow principal to the treasury (37 seconds)

**Screen and action.** Select **Remove liquidity and collect fees**, then **Withdraw both principal assets**. Compare the two receipts and the vault’s ending balances. Keep the manager route blocked.

> First, core sends the position’s assets and fees to the vault. The second receipt is the one that matters to the treasury. Including idle inventory, its wallet received about two thousand one hundred A and nineteen hundred B. Those assets came from the vault. The treasury needed no manager signature. That payment route remains blocked. Receipt of principal still depends on working contracts, a progressing chain and principal tokens that can transfer.

**Expected evidence.** Blocks 32–33. Vault removal includes 0.301038 A LP fees. Treasury receives 2,100.346049 A and 1,900.054977 B, with vault balances and owned liquidity now zero. [Balance reconciliation](A6-AUTHOR-REHEARSAL.md#financial-results-observed-in-both-rounds)

### 2:32–3:10 · Follow the refund and the reserve (38 seconds)

**Screen and action.** Select **Collect the unearned 40 B refund**. Pause on escrow’s 20 B balance. Select **Restore the manager payment route**, **Claim the preserved 20 B**, then the repeat claim and refund controls. **Build statement** and **Download JSON**.

> Now watch the separate pay budget. The treasury can take forty B of unearned funds. Twenty stays in escrow because it belongs to the manager. Restoring that transfer pays exactly twenty. Both repeat pulls move zero. The statement ties the service intervals, transfers and outstanding rights to the displayed block. You can download it and check the amounts. The refund moved part of an existing budget back to the treasury.

**Expected evidence.** Block 34 shows refunded 40 B and reserved 20 B. By block 38 manager receipts total 60 B, treasury refunds total 40 B and escrow holds zero. [Download reconciliation](LOCAL-VIEWER.md#checked-browser-downloads)

### 3:10–3:55 · Inspect two separate author runs (45 seconds)

**Screen and action.** Switch to the published **Round 1** receipt table. Show the **manager** row for `rerange` at block 26, then the *different* **swap** run ID and its outward and return receipts. Keep the run labels visible. [Run IDs and full transaction hashes](A6-AUTHOR-REHEARSAL.md#run-identities-and-receipts)

> These are two separate recorded author runs. In the manager run the vault checkpoints the old position first. The manager then extends the range within its limits. Salt one retires and salt two holds the same liquidity. Tick one hundred twenty is inside that wider position. In the separate swap run the seed stayed narrow. At that same tick it stopped qualifying. The return swap restored service at tick minus one. The clock stayed at ninety through the interruption.

**Expected evidence.** Manager run `0x0e15921c…`, mined rerange `0x6e63931e…`, new range [−180, 180) and 100,000,000,000 L. Swap run `0x98e2a246…`, blocks 25–27, Q=90 → 90 → 120. For the interactive equivalent, reset by the full current ID **between** paths. On a new funded identity activate, checkpoint the seed after 30 s, extend, then offer 700 B. On another fresh identity activate, interrupt at +90 s, return, then close at +240 s. [Manager controls](LOCAL-VIEWER.md#permitted-manager-rerange-on-a-fresh-run) · [Swap controls](LOCAL-VIEWER.md#interrupt-and-recover-on-a-separate-run)

### 3:55–4:30 · Compare the same job (35 seconds)

**Screen and action.** Show the M6 **Interrupted** row, then the payer table. Point out that **Early close, blocked payment** is a different row.

> Across seven scenarios the matched manager on a retainer delivered identical liquidity, fills and fees. Both arrangements let the treasury exit independently. In the full interrupted period the retainer paid one hundred B and Unison paid sixty. That onchain settlement cost about nine point four million extra gas including dedicated deployment and three swaps. Whether the invoice is worth that premium needs evidence from a treasury and a manager. Independent reproduction is also pending.

**Expected evidence.** Retainer and Unison both delivered Q=180 on the interrupted workload. Extra gas was 9,405,354 in total. In the separate early-close case both paid 60 B. [Matched rows](M6-COMPARISON.md#service-execution-and-settlement) · [Gas by payer](M6-COMPARISON.md#cost-by-payer-and-economic-hurdle)

**Timing estimate.** The seven spoken passages contain 505 whitespace-delimited words. At 135 words per minute they take about 3:44. Allow another 46 seconds for receipt waits, tab changes and silent inspection across the segments. Estimated total 4:30, with 30 seconds of margin. Human narration and final video timing are pending. The supplied limit is five minutes.

**If the live run stalls.** Show its last confirmed block. Say “The local demo stopped here. I’m switching to recorded transaction evidence from the author’s Round 1 payment run.” Open that run’s ID and blocks 26–38 in the receipt table, then its balances after termination, refund and restoration. Use its hashes throughout the fallback. For the manager and swap segments switch to their separately named rows. The records are written evidence from local transactions. A human-narrated video is pending. [Round 1 receipts](A6-AUTHOR-REHEARSAL.md#run-identities-and-receipts) · [Balances](A6-AUTHOR-REHEARSAL.md#financial-results-observed-in-both-rounds)

## Three-minute judge inspection

| Time | Open and inspect | Question answered |
| --- | --- | --- |
| 0:00–0:50 | Read Round 1 payment blocks 29, 31, 33, 34 and 36 alongside the balance table. Follow the 20 B across the refund. [Receipts](A6-AUTHOR-REHEARSAL.md#run-identities-and-receipts) · [Balances](A6-AUTHOR-REHEARSAL.md#financial-results-observed-in-both-rounds) | Did payment really fail, did the treasury receive principal, and who got the remaining money? |
| 0:50–1:35 | Inspect the separate extension and interruption runs. Compare tick 120 against each position’s upper edge. [Extension](LOCAL-VIEWER.md#permitted-manager-rerange-on-a-fresh-run) · [Interruption](LOCAL-VIEWER.md#interrupt-and-recover-on-a-separate-run) | Why does the same tick earn in one run and pause in the other? |
| 1:35–2:30 | Compare the interrupted, feasible recovery and early-close rows, then the interrupted payer totals. [Outcomes](M6-COMPARISON.md#service-execution-and-settlement) · [Cost](M6-COMPARISON.md#cost-by-payer-and-economic-hurdle) | Which benefit survived the matched retainer and what did it cost? |
| 2:30–3:00 | Check the patched runtime pin, author-only rehearsal and open reviewer, customer and video fields. [Submission checklist](M8-SUBMISSION.md) | Which claims can a judge reproduce and which still need human evidence? |
