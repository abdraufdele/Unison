"""Foreground owner of one disposable Anvil, with separate read and fixed-action interfaces."""
import json
import queue
import re
import secrets
import sys
from http.client import HTTPConnection
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from web3 import IPCProvider, Web3
from artifacts import build_id, fixture
from statement import EvidenceError, statement
from journey import Conflict, Journey, check

HOST = "127.0.0.1"
PORT = 18547
BASE = f"http://{HOST}:{PORT}"
ORIGIN = "http://127.0.0.1:5173"
READ_METHODS = {"eth_chainId", "eth_call", "eth_getCode", "eth_getBlockByNumber"}


class Reader(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def allowed(self):
        return self.headers.get_all("Host") == [f"{HOST}:{PORT}"] and self.headers.get_all("Origin") in (None, [ORIGIN])

    def send_json(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", ORIGIN)
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Unison-CSRF")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_json(200 if self.allowed() else 403, None)

    def do_GET(self):
        if not self.allowed():
            return self.send_json(403, None)
        if self.path == "/deployment.json":
            return self.send_json(200, self.server.manifest)
        if self.path.startswith("/statement/"):
            match = re.fullmatch(r"/statement/(0x[0-9a-f]{64})/([0-9]{1,12})/(0x[0-9a-f]{64})", self.path)
            if not match:
                return self.send_json(400, {"message": "Expected run ID, as-of number and block hash."})
            session = self.server.journey
            try:
                with session.lock:
                    data = statement(session, match[1], int(match[2]), match[3])
            except (EvidenceError, ValueError) as err:
                return self.send_json(409, {"message": str(err)})
            except Exception:
                return self.send_json(503, {"message": "Historical RPC or ABI decoding failed. Check the owned archive and retry."})
            return self.send_json(200, data)
        if self.path == "/controls" and self.headers.get_all("Origin") == [ORIGIN]:
            session = self.server.journey
            with session.lock:
                status = session.status()
            return self.send_json(200, status)
        self.send_json(404, None)

    def control(self):
        session = self.server.journey
        if (not self.allowed() or self.headers.get_all("Origin") != [ORIGIN]
                or self.headers.get_content_type() != "application/json"
                or self.headers.get_all("X-Unison-CSRF") != [session.csrf]):
            return self.send_json(403, {"message": "Control origin or run token rejected. Refresh this run."})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 1024:
                return self.send_json(413, {"message": "Invalid action size."})
            body = json.loads(self.rfile.read(size))
            reset = self.path == "/controls/reset"
            field = "confirmation" if reset else "action"
            if not isinstance(body, dict) or set(body) != {"runId", "version", field} or not isinstance(body[field], str):
                raise ValueError("Invalid action fields.")
        except (ValueError, TypeError):
            return self.send_json(400, {"message": "Expected a fixed action and the current run and version."})
        if not session.lock.acquire(blocking=False):
            return self.send_json(409, {"message": "Another action is in progress. Refresh its receipt."})
        try:
            if reset:
                session.validate(body)
                check(body[field] == session.manifest["runId"], "Enter the exact current run ID to reset.")
                session.closing = True
                self.server.events.put(("reset", session))
                response = {"resetting": True}
            else:
                response = session.perform(body)
        except (Conflict, ValueError) as exc:
            return self.send_json(409, {"message": str(exc)})
        except Exception:
            return self.send_json(503, {"message": "Controller could not verify the action. Refresh the receipt history before continuing."})
        finally:
            session.lock.release()
        self.send_json(200, response)

    def do_POST(self):
        if self.path in ("/controls/action", "/controls/reset"):
            return self.control()
        if not self.allowed() or self.path != "/rpc":
            return self.send_json(403, None)
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 131072:
                return self.send_json(413, None)
            payload = json.loads(self.rfile.read(size))
            batch = isinstance(payload, list)
            calls = payload if batch else [payload]
            if not 0 < len(calls) <= 128:
                return self.send_json(400, None)
            replies = []
            for call in calls:
                method = call["method"]
                if method not in READ_METHODS:
                    result = {"error": {"code": -32601, "message": "Read-only local endpoint"}}
                else:
                    result = self.server.reader.make_request(method, call.get("params", []))
                replies.append({**result, "jsonrpc": "2.0", "id": call["id"]})
            self.send_json(200, replies if batch else replies[0])
        except (KeyError, ValueError, TypeError):
            self.send_json(400, None)
        except (OSError, TimeoutError):
            self.send_json(503, {"message": "Owned Anvil unavailable"})


def block_hash(block):
    return Web3.to_hex(block.hash)


def manifest(run, marker):
    addresses = {key: obj.address for key, obj in {
        "vault": run.v, "escrow": run.esc, "hook": run.hook, "core": run.core,
        "tokenA": run.a, "tokenB": run.b, "lens": run.router,
    }.items()}
    vault = run.w.eth.contract(address=run.v.address, abi=run.v.abi, decode_tuples=True)
    addresses["adapter"] = vault.functions.currentTerms().call().bindings.referenceAdapter
    block = run.w.eth.get_block("latest")
    return {"schema": 1, "endpoint": BASE + "/rpc", "chainId": 31337, "runId": Web3.to_hex(marker),
            "anchor": {"number": str(block.number), "hash": block_hash(block)},
            "buildId": build_id(), "addresses": addresses,
            "codeHashes": {k: Web3.to_hex(Web3.keccak(run.w.eth.get_code(a))) for k, a in addresses.items()}}


def verify(server, run, deployment):
    w = run.w
    if (server.server_address != (HOST, PORT) or server.manifest != deployment
            or w.client_version != "anvil/v1.8.7" or w.eth.chain_id != deployment["chainId"]
            or w.eth.block_number < int(deployment["anchor"]["number"])
            or block_hash(w.eth.get_block(int(deployment["anchor"]["number"]))) != deployment["anchor"]["hash"]
            or Web3.to_hex(run.v.functions.agreementId().call()) != deployment["runId"]):
        raise ValueError("Run identity changed. Stop this launcher and start a new owned run.")

    a = deployment["addresses"]
    vault = w.eth.contract(address=run.v.address, abi=run.v.abi, decode_tuples=True)
    t = vault.functions.currentTerms().call()
    b = t.bindings
    check((t.vault, b.escrow, b.hook, b.poolManager, b.token0, b.token1, b.referenceAdapter, run.router.address)
          == tuple(a[key] for key in ("vault", "escrow", "hook", "core", "tokenA", "tokenB", "adapter", "lens")),
          "Product bindings changed.")
    check(run.v.functions.termsHash().call() == run.h,
          "Terms changed.")
    check(t.treasury == t.treasuryRecipient == run.esc.functions.treasuryRecipient().call() == run.owner
          and t.manager == t.managerRecipient == run.esc.functions.managerRecipient().call() == run.actors["manager"]
          and run.hook.functions.vault().call() == run.esc.functions.vault().call() == t.vault
          and run.esc.functions.paymentToken().call() == b.token1
          and run.hook.functions.poolManager().call() == b.poolManager, "Actor or custody binding changed.")
    check(all(Web3.to_hex(Web3.keccak(w.eth.get_code(addr))) == deployment["codeHashes"][key]
              for key, addr in a.items()), "Runtime code changed.")


def inspect(run):
    block = run.w.eth.block_number
    def read(fn):
        return fn.call(block_identifier=block)
    live = run.router.functions.position(run.key, run.v.address, read(run.v.functions.positionLower()),
                                         read(run.v.functions.positionUpper()), read(run.v.functions.positionSalt()))
    _, tick, _, owned, *_ = read(live)
    fields = {"block": block, "state": read(run.v.functions.state()), "tick": tick,
              "ownedL": owned, "qualification": read(run.hook.functions.qualification()),
              "persisted": read(run.hook.functions.qualifyingSeconds()), "projected": read(run.hook.functions.projectedSeconds())}
    for name in ("fundedBudget", "earned", "claimed", "reserved", "claimable", "refunded", "refundable"):
        fields[name] = read(getattr(run.esc.functions, name)())
    for key, obj in (("vault", run.v), ("escrow", run.esc)):
        fields[key] = [read(t.functions.balanceOf(obj.address)) for t in (run.a, run.b)]
    print(json.dumps(fields), flush=True)


def terminal_input(events):
    for line in sys.stdin:
        events.put(("command", line.strip()))
    events.put(("command", "stop"))


def commands(server, session):
    run_id = session.manifest["runId"]
    print(f"Ready {BASE}/deployment.json\nRun {run_id}\nCommands: inspect, activate, interrupt, terminate, reset <run-id>, stop", flush=True)
    while True:
        kind, value = server.events.get()
        if kind == "reset":
            if value is session:
                return True
            continue
        if value == "stop":
            return False
        if value == "inspect":
            with session.lock:
                session.verify()
                inspect(session.run)
            continue
        # Legacy terminal shortcuts use the very same authenticated, stage-checked dispatcher.
        body = {"runId": run_id, "version": len(session.history)}
        path = "/controls/action"
        if value.startswith("reset "):
            body["confirmation"] = value[6:]
            path = "/controls/reset"
        elif value in ("activate", "interrupt", "terminate"):
            body["action"] = "shortClose" if value == "terminate" and session.stage in ("activate", "interrupt") else value
        else:
            print("Unknown command.", flush=True)
            continue
        conn = HTTPConnection(HOST, PORT, timeout=20)
        try:
            conn.request("POST", path, json.dumps(body), {"Origin": ORIGIN, "Content-Type": "application/json",
                                                         "X-Unison-CSRF": session.csrf})
            result = json.load(conn.getresponse())
            print(result.get("message", f"State {session.stage}"), flush=True)
        finally:
            conn.close()


def main():
    with ThreadingHTTPServer((HOST, PORT), Reader) as server:
        server.events = queue.Queue()
        threading.Thread(target=terminal_input, args=(server.events,), daemon=True).start()
        while True:
            with fixture.chain(viewer=True) as w:
                run = fixture.Run(w)
                marker = secrets.token_bytes(32)
                run.setup("C", agreement_id=marker, funded_only=True)
                deployment = manifest(run, marker)
                server.manifest = deployment
                server.reader = IPCProvider(w.provider.ipc_path, timeout=5)
                session = Journey(run, deployment, lambda: verify(server, run, deployment))
                server.journey = session
                session.verify()
                worker = threading.Thread(target=server.serve_forever)
                worker.start()
                try:
                    restart = commands(server, session)
                finally:
                    with session.lock:
                        session.closing = True
                    server.shutdown()
                    worker.join()
                if not restart:
                    return


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
