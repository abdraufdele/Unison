"""Read-only statement for the pinned C1 build. All quantities stay integral until JSON encoding."""
from collections import Counter, defaultdict
from collections.abc import Mapping
from functools import lru_cache

from web3 import Web3

from artifacts import build_id


class EvidenceError(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise EvidenceError(message)


def wire(value):
    if isinstance(value, bytes):
        return Web3.to_hex(value)
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return str(value)
    if hasattr(value, "_asdict"):
        value = value._asdict()
    if isinstance(value, Mapping):
        return {k: wire(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [wire(v) for v in value]
    return value


def header(b):
    return {"number": b.number, "hash": b.hash, "parentHash": b.parentHash,
            "timestamp": b.timestamp, "transactionCount": len(b.transactions)}


def creation_block(run, funded):
    eth = run.w.eth
    lo, hi = 0, funded
    while lo < hi:
        mid = (lo + hi) // 2
        if eth.get_code(run.v.address, block_identifier=mid):
            hi = mid
        else:
            lo = mid + 1
    require(lo > 0 and eth.get_code(run.v.address, block_identifier=lo), "Missing vault deployment code.")
    return lo


def match_logs(queried, recorded):
    ids = [(x.blockNumber, x.transactionIndex, x.logIndex) for x in queried]
    require(len(ids) == len(set(ids)), "Duplicate product log.")
    require(ids == sorted(ids), "Product logs arrived out of order.")
    def content(x):
        return (x.blockHash, x.transactionHash, x.transactionIndex, x.logIndex, x.address,
                tuple(x.topics), x.data, x.get("removed", False))
    require(all(not x.get("removed") for x in queried) and
            [content(x) for x in queried] == [content(x) for x in recorded],
            "Incomplete or inconsistent product logs versus canonical block receipts.")


def history(run, first, last, journal):
    eth = run.w.eth
    decoders = {c.address: {Web3.to_bytes(hexstr=event.topic): event for event in c.events}
                for c in (run.v, run.hook, run.esc)}
    queries = []
    for low in range(first, last + 1, 8):
        high = min(low + 7, last)
        rows = eth.get_logs({"address": list(decoders), "fromBlock": low, "toBlock": high})
        require(all(low <= x.blockNumber <= high for x in rows), "Log outside requested range.")
        queries.extend(rows)
        require(len(queries) <= 1024, "Statement exceeds 1024 product logs.")
    blocks, logs, failed = {}, [], []
    known = {r["hash"]: r for r in journal if not r["success"] and r["block"] <= last}
    deployed = False
    for n in range(first, last + 1):
        b = eth.get_block(n)
        require(b.number == n and (n == first or b.parentHash == blocks[n-1].hash), "Block ancestry changed.")
        blocks[n] = b
        require(len(b.transactions) <= 8, "Block exceeds the local receipt scan limit.")
        for index, tx in enumerate(b.transactions):
            r = eth.get_transaction_receipt(tx)
            require(r.blockHash == b.hash and r.blockNumber == n and r.transactionHash == tx
                    and r.transactionIndex == index, "Receipt does not belong to the requested block.")
            if n == first and r.status and r.contractAddress == run.v.address:
                deployed = True
            for log in r.logs:
                if log.address in decoders:
                    require(r.status and log.blockHash == b.hash and log.blockNumber == n and
                            log.transactionHash == tx and log.transactionIndex == index, "Invalid receipt log.")
                    logs.append(log)
            entry = known.pop(Web3.to_hex(tx), None)
            if entry:
                require(r.status == 0 and not r.logs and r.to == entry["target"] and r["from"] == entry["sender"]
                        and entry["block"] == n, "Demo failure history disagrees with its mined receipt.")
                failed.append({**{k: entry[k] for k in ("action", "hash", "sender", "target", "error", "revertData")},
                               "block": n, "blockHash": b.hash, "timestamp": b.timestamp,
                               "transactionIndex": index, "status": "reverted"})
    require(deployed and not known, "Missing creation receipt or known failure receipt.")
    match_logs(queries, logs)
    events = []
    for x in queries:
        decoder = decoders[x.address].get(x.topics[0])
        require(decoder is not None, "Unknown product event in pinned build.")
        decoded = decoder.process_log(x)
        events.append({"name": decoded.event, "args": dict(decoded.args), "address": x.address,
                       "block": x.blockNumber, "blockHash": x.blockHash, "timestamp": blocks[x.blockNumber].timestamp,
                       "transactionHash": x.transactionHash, "transactionIndex": x.transactionIndex, "logIndex": x.logIndex})
    return events, blocks, failed


def split_delta(value):
    # v4 BalanceDelta packs two signed int128 legs into one int256.
    return (value >> 128, ((value + (1 << 127)) % (1 << 128)) - (1 << 127))


def movements(run, events, blocks, terms):
    rows, deltas = [], defaultdict(Counter)
    a = terms.bindings
    def move(kind, token, sender, recipient, amount):
        require(amount >= 0, "Negative transfer amount.")
        rows.append({"kind": kind, "token": token.address, "sender": sender, "recipient": recipient,
                     "amount": amount, "eventIndex": index})
        deltas[event["block"]][token.address, sender] -= amount
        deltas[event["block"]][token.address, recipient] += amount

    for index, event in enumerate(events):
        name, x = event["name"], event["args"]
        if name == "Funded":
            move("Fund principal", run.a, terms.treasury, run.v.address, x["principal0"])
            move("Fund principal", run.b, terms.treasury, run.v.address, x["principal1"])
            move("Fund compensation", run.b, terms.treasury, a.escrow, x["budget"])
        elif name in ("CompensationClaimed", "BudgetRefunded"):
            recipient = terms.managerRecipient if name == "CompensationClaimed" else terms.treasuryRecipient
            require(x["recipient"] == recipient, "Unexpected settlement recipient.")
            move(name, run.b, a.escrow, recipient, x["amount"])
        elif name == "IdleWithdrawn":
            require(x["recipient"] == terms.treasuryRecipient, "Unexpected treasury withdrawal recipient.")
            for i, token in enumerate((run.a, run.b)):
                move("Treasury withdrawal", token, run.v.address, x["recipient"], x[f"amount{i}"])
        elif name in ("Activated", "PositionAdjusted", "LiquidityExited"):
            if name == "Activated":
                principal, fees = [-x["amount0"], -x["amount1"]], [0, 0]
            elif name == "PositionAdjusted":
                principal, fees = split_delta(x["principal"]), split_delta(x["fees"])
            else:
                principal, fees = [x["principal0"], x["principal1"]], [x["fees0"], x["fees1"]]
            for i, token in enumerate((run.a, run.b)):
                net = principal[i] + fees[i]
                sender, recipient = (a.poolManager, run.v.address) if net >= 0 else (run.v.address, a.poolManager)
                move(name, token, sender, recipient, abs(net))
                rows[-1].update(vaultPrincipalDelta=principal[i], vaultFeeDelta=fees[i])
    @lru_cache(None)
    def balance(token, addr, n):
        contract = run.a if token == run.a.address else run.b
        return contract.functions.balanceOf(addr).call(block_identifier=n)
    for n, accounts in deltas.items():
        require(len(blocks[n].transactions) == 1, "Cannot isolate transfers in a multi-transaction block.")
        for (token, addr), delta in accounts.items():
            require(balance(token, addr, n) - balance(token, addr, n-1) == delta,
                    f"Token balance change disagrees with movement records at block {n}.")
    return rows


def service(run, events, activation, close, terms, as_of):
    checkpoints = [(i, e) for i, e in enumerate(events) if e["name"] == "ServiceCheckpoint"]
    if not activation:
        require(not checkpoints, "Clock checkpoint before activation.")
        return [], 0, 0
    a = activation["args"]
    first, end = a["start"], a["end"]
    stop = close["args"]["effectiveStop"] if close else end
    require(first <= stop <= end and end-first == terms.parameters.duration, "Invalid service period.")
    require(checkpoints and checkpoints[0][1]["transactionHash"] == activation["transactionHash"],
            "Missing activation checkpoint.")
    positions = {}
    for event in events:
        if event["name"] in ("Activated", "PositionAdjusted"):
            x = event["args"]
            position = Web3.keccak(run.w.codec.encode(["bytes32","address","int24","int24","bytes32"],
                                   [a["poolId"], run.v.address, x["lower"], x["upper"], x["salt"]]))
            positions[position] = (x["lower"], x["upper"])
    intervals = []
    prev, total, qualified, reasons, source = first, 0, False, [], None
    def interval(to, kind, ending):
        nonlocal total
        require(prev <= to <= stop, "Checkpoint outside service period.")
        if to > prev:
            total += (to-prev) if qualified else 0
            intervals.append({"from": prev, "to": to, "qualified": qualified, "reasons": reasons,
                              "kind": kind, "secondsCredited": to-prev if qualified else 0, "cumulativeQ": total,
                              "fromEvent": source, "toEvent": ending})
    for index, event in checkpoints:
        x = event["args"]
        require(x["oldQualified"] == qualified and x["at"] == min(event["timestamp"], stop),
                "Checkpoint time or old qualification disagrees with history.")
        interval(x["at"], "persisted", index)
        require(x["qualifyingSeconds"] == total, "Checkpoint cumulative Q disagrees with interval sum.")
        prev, qualified, source = x["at"], x["newQualified"], index
        reasons = []
        edges = positions.get(x["positionId"])
        if close and (event["block"], event["transactionIndex"]) >= (close["block"], close["transactionIndex"]):
            reasons.append("period closed")
        if prev >= end:
            reasons.append("scheduled end reached")
        if not edges or x["liquidity"] == 0:
            reasons.append("no matching live position")
        if x["liquidity"] < terms.parameters.minLiquidity:
            reasons.append("below minimum liquidity")
        if edges:
            lo, hi = edges
            if not lo <= x["tick"] < hi:
                reasons.append("tick outside position")
            if lo > a["lower"] or hi < a["upper"]:
                reasons.append("opening band uncovered")
            p = terms.parameters
            if (lo < a["lower"]-p.maxEdgeExtensionTicks or hi > a["upper"]+p.maxEdgeExtensionTicks
                    or hi-lo > p.maxWidthTicks or lo % p.tickSpacing or hi % p.tickSpacing):
                reasons.append("range outside permitted bounds")
        require(not (qualified and reasons), "Observed qualification disagrees with checkpoint evidence.")
        if not qualified and not reasons:
            reasons.append("additional qualification predicate; exact failure mask was not emitted")
        event["qualificationReasons"] = reasons
    persisted = total
    interval(min(as_of, stop), "projected", None)
    return intervals, persisted, total


def statement(session, run_id, number, block_hash):
    run, m = session.run, session.manifest
    require(m["schema"] == 1 and m["buildId"] == build_id(), "Unsupported deployment schema or build.")
    require(not session.closing and run_id == m["runId"], "Statement belongs to a different or closing run.")
    # Keep the launcher identity checks used by writes, but never invoke a write or time control.
    session.verify()
    eth = run.w.eth
    anchor = int(m["anchor"]["number"])
    require(anchor <= number <= eth.block_number, "As-of block is outside the funded run.")
    last = eth.get_block(number)
    require(Web3.to_hex(last.hash) == block_hash, "As-of block hash changed.")
    first = creation_block(run, anchor)
    require(number-first < 128, "Incomplete coverage: maximum 128 blocks per local statement.")
    events, blocks, failed = history(run, first, number, session.history)
    require(blocks[number].hash == last.hash and Web3.to_hex(blocks[anchor].hash) == m["anchor"]["hash"],
            "Funded or as-of block changed during receipt scan.")
    vault = run.w.eth.contract(address=run.v.address, abi=run.v.abi, decode_tuples=True)
    def read(fn):
        return fn.call(block_identifier=number)
    terms, terms_hash = read(vault.functions.currentTerms()), read(vault.functions.termsHash())
    require(Web3.to_hex(terms.agreementId) == run_id and terms.chainId == m["chainId"], "Agreement mismatch.")

    def single(name, required=True):
        found = [e for e in events if e["name"] == name]
        require(len(found) == 1 if required else len(found) <= 1, f"Missing or repeated {name} event.")
        return found[0] if found else None
    publications = [e for e in events if e["name"] == "TermsPublished"]
    require(publications and publications[0]["block"] == first and
            [e["args"]["revision"] for e in publications] == list(range(1, terms.revision+1)) and
            publications[-1]["args"]["termsHash"] == terms_hash, "Missing or inconsistent terms revision.")
    funding, credit = single("Funded"), single("BudgetCredited")
    f = funding["args"]
    accepts = [e for e in events if e["name"] == "PartyAccepted" and e["args"]["revision"] == terms.revision]
    require(len(accepts) == 2 and {e["args"]["party"] for e in accepts} == {terms.treasury, terms.manager}
            and all(e["args"]["termsHash"] == terms_hash and events.index(publications[-1]) < events.index(e)
                    < events.index(funding) for e in accepts), "Missing or inconsistent acceptance evidence.")
    budget = f["budget"]
    require(funding["block"] == anchor and f["termsHash"] == terms_hash and f["revision"] == terms.revision
            and f["escrow"] == run.esc.address and credit["transactionHash"] == funding["transactionHash"]
            and credit["args"] == {"token": run.b.address, "amount": budget}
            and (f["principal0"], f["principal1"], budget) ==
                (terms.parameters.inventory0, terms.parameters.inventory1, terms.parameters.budget),
            "Funding disagrees with accepted terms or escrow credit.")
    activation, opening = single("Activated", False), single("OpeningFixed", False)
    close, cancel = single("PeriodClosed", False), single("Cancelled", False)
    require(bool(activation) == bool(opening), "Incomplete opening observation.")
    start, end, stop = 0, 0, 0
    phase = "Cancelled" if cancel else "Funded"
    if activation:
        a = activation["args"]
        start, end = a["start"], a["end"]
        require(not cancel and activation["timestamp"] == start and a["termsHash"] == terms_hash and
                opening["transactionHash"] == activation["transactionHash"] and
                a["poolId"] == read(run.hook.functions.poolId()) and
                (a["lower"], a["upper"]) == (read(vault.functions.bandLower()), read(vault.functions.bandUpper())),
                "Activation evidence differs from contract.")
        phase = "Expired" if last.timestamp >= end else "Active"
        if close:
            stop = close["args"]["effectiveStop"]
            phase = "Terminated" if stop < end else "Expired"
            require(close["args"]["reason"] == (5 if phase == "Terminated" else 6)
                    and stop == min(close["timestamp"], end), "Close reason or stop inconsistent.")
        elif phase == "Expired":
            stop = end
    else:
        require(not close, "Close event without activation.")
    intervals, persisted, q = service(run, events, activation, close, terms, last.timestamp)
    duration = terms.parameters.duration
    earned = budget*q//duration
    claimed = refunded = 0
    for event in events:
        if event["name"] in ("CompensationClaimed", "BudgetRefunded"):
            at = event["timestamp"]
            seconds = sum(max(0, min(i["to"], at)-i["from"]) for i in intervals if i["qualified"])
            due = budget*seconds//duration
            amount = event["args"]["amount"]
            if event["name"] == "CompensationClaimed":
                require(amount > 0 and amount == due-claimed, "Claim differs from earned entitlement.")
                claimed += amount
            else:
                require((cancel or stop and at >= stop) and amount > 0 and amount == budget-due-refunded,
                        "Refund differs from terminal entitlement.")
                refunded += amount
    rows = movements(run, events, blocks, terms)
    derived = {"funded": budget, "persistedQ": persisted, "q": q, "earned": earned, "claimed": claimed,
               "refunded": refunded, "reserved": earned-claimed, "claimable": earned-claimed,
               "refundable": budget-earned-refunded if cancel or stop else 0,
               "escrowB": budget-claimed-refunded, "start": start, "end": end, "effectiveStop": stop,
               "lifecycle": phase}
    e, h, v = run.esc.functions, run.hook.functions, vault.functions
    observed = {k: read(fn) for k, fn in {
        "funded": e.fundedBudget(), "persistedQ": h.qualifyingSeconds(), "q": h.projectedSeconds(),
        "earned": e.earned(), "claimed": e.claimed(), "refunded": e.refunded(), "reserved": e.reserved(),
        "claimable": e.claimable(), "refundable": e.refundable(), "escrowB": run.b.functions.balanceOf(run.esc.address),
        "start": v.start(), "end": v.scheduledEnd(), "effectiveStop": v.effectiveStop()}.items()}
    observed["lifecycle"] = ["Draft","Accepted","Funded","Cancelled","Active","Terminated","Expired"][read(v.state())]
    # Derive the installed position from vault events and compare its actual size with the core read in the page.
    owned = 0
    for event in events:
        if event["name"] in ("Activated", "PositionAdjusted"):
            owned = event["args"]["liquidity"]
        elif event["name"] == "LiquidityExited":
            require(owned == event["args"]["liquidity"], "Exit size disagrees with installed liquidity.")
            owned = 0
    derived["ownedLiquidity"] = owned
    observed["ownedLiquidity"] = read(v.positionLiquidity())
    tokens, custody = [], {}
    for symbol, token in (("Mock A",run.a), ("Mock B",run.b)):
        tokens.append({"symbol": symbol, "address": token.address, "decimals": read(token.functions.decimals())})
        custody[token.address] = {role: read(token.functions.balanceOf(addr)) for role, addr in
                                  (("vault",run.v.address), ("escrow",run.esc.address),
                                   ("treasury",terms.treasuryRecipient), ("manager",terms.managerRecipient))}
        initial = token.functions.balanceOf(run.v.address).call(block_identifier=first-1)
        custody[token.address]["vaultBeforeDeploymentBlock"] = initial
        net = sum(row["amount"] * ((row["recipient"] == run.v.address) - (row["sender"] == run.v.address))
                  for row in rows if row["token"] == token.address)
        require(initial + net == custody[token.address]["vault"], "Unexplained vault balance outside product movements.")
    for key in derived:
        require(derived[key] == observed[key], f"Reconciliation mismatch for {key}.")
    require(eth.get_block(number).hash == last.hash, "As-of hash changed during reconstruction.")
    return wire({"schema": "unison.c1.statement.v1", "runId": run_id, "chainId": m["chainId"],
                 "buildId": m["buildId"], "endpoint": m["endpoint"], "addresses": m["addresses"],
                 "coverage": {"deployment": header(blocks[first]), "fundedAnchor": header(blocks[anchor]),
                              "asOf": header(last), "blocks": [header(b) for b in blocks.values()]},
                 "tokens": tokens, "custodyAtAsOf": custody,
                 "terms": terms, "termsHash": terms_hash, "events": events, "intervals": intervals,
                 "closeEventEmitted": bool(close), "movements": rows, "calculation": "floor(funded * q / originalDuration)",
                 "derived": derived, "contractReads": observed, "reconciliation": "matched",
                 "knownFailedReceipts": failed,
                 "provenance": "Owned Anvil IPC, pinned compiled product ABIs, ordered product logs cross-checked against mined receipts. Failed call explanations come from the local demo journal and its receipt trace.",
                 "limitations": ["One local node supplies blocks, receipts, logs and historical state. Agreement between these sources cannot prove provider completeness.",
                                 "Mock tokens emit no Transfer events. Transfer amounts use product events and sender/recipient balance changes in single-transaction blocks.",
                                 "Checkpoint events emit qualification and observations, without a full historical failure bitmask.",
                                 "Failure coverage is limited to recorded demo actions. Reverted calls produce no retained product logs.",
                                 "Service measures position conditions. M6 measured matching liquidity under the bounded retainer; buyer economics remain open."]})
