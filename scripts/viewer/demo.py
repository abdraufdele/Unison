"""Start one foreground local fixture. Browser RPC and terminal controls are separate."""
import json
import secrets
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

from web3 import IPCProvider, Web3
from artifacts import build_id, fixture

HOST = "127.0.0.1"
PORT = 18547
BASE = f"http://{HOST}:{PORT}"
ORIGIN = "http://127.0.0.1:5173"
READ_METHODS = {"eth_chainId", "eth_call", "eth_getCode", "eth_getBlockByNumber"}


class Reader(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def allowed(self):
        return self.headers.get("Host") == f"{HOST}:{PORT}" and self.headers.get("Origin") in (None, ORIGIN)

    def send_json(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", ORIGIN)
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_json(200 if self.allowed() else 403, None)

    def do_GET(self):
        if not self.allowed() or self.path != "/deployment.json":
            return self.send_json(404, None)
        self.send_json(200, self.server.manifest)

    def do_POST(self):
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


def commands(server, run, deployment):
    stage = "funded"
    run_id = deployment["runId"]
    print(f"Ready {BASE}/deployment.json\nRun {run_id}\nCommands: inspect, activate, interrupt, terminate, reset <run-id>, stop", flush=True)
    while True:
        try:
            command = input().strip()
        except EOFError:
            return False
        if command == "stop":
            return False
        try:
            verify(server, run, deployment)
            if command == "inspect":
                inspect(run)
            elif command == f"reset {run_id}":
                return True
            elif command == "activate" and stage == "funded":
                run.tx("treasury", "activate", run.v.functions.activate(run.h), 2000)
                run.rpc("evm_setNextBlockTimestamp", [2001])
                run.rpc("evm_mine", [])
                stage = "qualifying"
            elif command == "interrupt" and stage == "qualifying":
                run.tx("trader", "outward", run.router.functions.order(run.key, False, 700 * fixture.UNIT, 120), 2090)
                stage = "interrupted"
            elif command == "terminate" and stage in ("qualifying", "interrupted"):
                run.tx("treasury", "terminate", run.v.functions.terminate(), 2180)
                stage = "terminal"
            else:
                print(f"Unavailable at {stage}, or reset ID does not match.", flush=True)
                continue
            print(f"State {stage}", flush=True)
        except ValueError as error:
            print(str(error), flush=True)


def main():
    # Reserve the public read port before creating any chain or changing any state.
    with HTTPServer((HOST, PORT), Reader) as server:
        while True:
            with fixture.chain(viewer=True) as w:
                run = fixture.Run(w)
                marker = secrets.token_bytes(32)
                run.setup("C", agreement_id=marker, funded_only=True)
                deployment = manifest(run, marker)
                server.manifest = deployment
                server.reader = IPCProvider(w.provider.ipc_path, timeout=5)
                verify(server, run, deployment)
                worker = threading.Thread(target=server.serve_forever)
                worker.start()
                try:
                    restart = commands(server, run, deployment)
                finally:
                    server.shutdown()
                    worker.join()
                if not restart:
                    return


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
