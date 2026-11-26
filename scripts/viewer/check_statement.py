"""Replay explicit scenarios on private, launcher-owned test chains; keep an existing demo intact."""
import argparse
import json
import secrets
import subprocess
import threading
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from unittest.mock import patch

from web3 import IPCProvider

import demo
from artifacts import ROOT, fixture
from journey import Journey
from statement import EvidenceError, statement


# Run the Chromium download checks against this isolated statement server.
def checkExport(server, session, case):
    subprocess.run(["node", str(ROOT/"viewer/check-statement.mjs"), str(server.server_port), case,
                    session.manifest["runId"]], cwd=ROOT, check=True, timeout=55)


# Challenge event completeness, uniqueness and ordering against actual receipts.
def faults(session):
    eth = session.run.w.eth
    head = eth.get_block("latest")
    args = (session, session.manifest["runId"], head.number, demo.blockHash(head))
    original = eth.get_logs
    for mode, message in (("missing","Incomplete"), ("duplicate","Duplicate"), ("order","order")):
        # Alter one log response to exercise the selected statement rejection.
        def damaged(query):
            records = original(query)
            if len(records) < 2:
                return records
            if mode == "duplicate":
                return records + records[-1:]
            return records[1:] if mode == "missing" else list(reversed(records))
        with patch.object(eth, "get_logs", damaged):
            try:
                statement(*args)
            except EvidenceError as e:
                assert message in str(e), str(e)
            else:
                raise AssertionError(mode)
    print("Missing, duplicate and out-of-order queries rejected against actual product receipts.", flush=True)


# Create an isolated funded run and exercise the requested statement scenario.
def replay(server, scenario):
    with fixture.chain(viewer=True) as w:
        run = fixture.Run(w)
        marker = secrets.token_bytes(32)
        run.setup("C", agreement_id=marker, funded_only=True)
        m = demo.manifest(run, marker)
        session = Journey(run, m, lambda: demo.verify(server, run, m))
        server.manifest, server.journey = m, session
        server.reader = IPCProvider(w.provider.ipc_path, timeout=5)
        session.verify()
        # Submit one fixed action with the session identity and expected journal version.
        def act(action):
            conn = HTTPConnection(demo.HOST, server.server_port, timeout=15)
            try:
                conn.request("POST", "/controls/action",
                             json.dumps({"action": action, "runId": m["runId"], "version": len(session.history)}),
                             {"Origin": demo.ORIGIN, "Content-Type":"application/json", "X-Unison-CSRF":session.csrf})
                reply = conn.getresponse()
                data = json.load(reply)
                assert reply.status == 200 and data["stage"] == action, (action, data.get("message"))
            finally:
                conn.close()
        if scenario == "manager":
            checkExport(server, session, scenario)
            from check_manager import reconcileManager
            reconcileManager(run, session)
            return
        if scenario == "payment":
            checkExport(server, session, "funded")
        act("activate")
        if scenario == "expiry":
            # Test-only explicit observation, on this test's own IPC. No finalization transaction.
            run.rpc("evm_setNextBlockTimestamp", [2307])
            run.rpc("evm_mine", [])
            checkExport(server, session, "expiry")
        elif scenario == "swap":
            for action in ("interrupt", "return", "returnClose"):
                act(action)
            checkExport(server, session, "swap")
        else:
            checkExport(server, session, "active")
            for action in ("trade","claim40","checkpoint","block","failedClaim","terminate","revoked",
                           "remove","withdraw","refund","restore","claim20","repeatClaim","repeatRefund"):
                act(action)
                if action in ("terminate","refund","repeatRefund"):
                    checkExport(server, session, action)
            faults(session)


if __name__ == "__main__":
    # Chromium routes the fixed frontend gateway origin to this actual Reader instance in its test context.
    # The manifest keeps the production browser endpoint. The OS selects an isolated loopback listener.
    parser = argparse.ArgumentParser()
    parser.add_argument("cases", nargs="*", help="Optional scenarios: payment, swap, expiry, manager")
    cases = parser.parse_args().cases or ["payment", "swap", "expiry", "manager"]
    if set(cases) - {"payment", "swap", "expiry", "manager"}:
        parser.error("Unknown scenario")
    with ThreadingHTTPServer((demo.HOST, 0), demo.Reader) as server:
        demo.PORT = server.server_port
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        try:
            for case in cases:
                replay(server, case)
        finally:
            server.shutdown()
            worker.join()
