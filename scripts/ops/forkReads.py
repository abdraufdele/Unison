"""Limit the fork's upstream connection to Ethereum reads and keep private provider URLs out of child commands."""

import json
import secrets
import threading
import sys
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from web3 import Web3

READS = {
    "eth_chainId",
    "net_version",
    "eth_blockNumber",
    "eth_getBlockByNumber",
    "eth_getBlockByHash",
    "eth_getCode",
    "eth_getBalance",
    "eth_getStorageAt",
    "eth_getTransactionCount",
    "eth_getProof",
    "eth_getTransactionByHash",
    "eth_getTransactionReceipt",
    "eth_getBlockReceipts",
    "eth_getLogs",
    "eth_gasPrice",
    "eth_feeHistory",
    "eth_maxPriorityFeePerGas",
    "eth_call",
    "web3_clientVersion",
}


# Forward one allowlisted read, preserving the client's request ID and hiding endpoint credentials on errors.
def forwardRead(provider, query):
    method = query.get("method")
    reply = {"jsonrpc": "2.0", "id": query.get("id")}
    if method not in READS:
        return dict(reply, error={"code": -32601, "message": "unsupported fork read " + str(method)})
    try:
        upstream = provider.make_request(method, query.get("params", []))
    except Exception as exc:
        print(f"Fork read {method} failed ({type(exc).__name__})",file=sys.stderr,flush=True)
        return dict(reply, error={"code": -32000, "message": "upstream read failed for " + method})
    if "error" in upstream:
        print(f"Fork read {method} returned RPC {upstream['error']['code']}",file=sys.stderr,flush=True)
        return dict(
            reply, error={"code": upstream["error"]["code"], "message": "upstream rejected " + method}
        )
    return dict(reply, result=upstream["result"])


# Start the read listener only for an owned fork and shut it down with the simulation.
@contextmanager
def forkReads(url):
    provider = Web3.HTTPProvider(url, request_kwargs={"timeout": 15},exception_retry_configuration=None)
    path = "/" + secrets.token_urlsafe(24)

    class Reader(BaseHTTPRequestHandler):
        # The standard server dispatches this method for RPC POST requests on the ephemeral path.
        def do_POST(self):
            size = int(self.headers.get("Content-Length", 0))
            if self.path != path or not 0 < size <= 131072:
                self.send_error(404)
                return
            query = json.loads(self.rfile.read(size))
            result = (
                [forwardRead(provider, q) for q in query]
                if isinstance(query, list)
                else forwardRead(provider, query)
            )
            body = json.dumps(result).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                return

        # Suppress the base HTTP handler's logging of the ephemeral request path.
        def log_message(self, format, *args):
            pass

    with ThreadingHTTPServer(("127.0.0.1", 0), Reader) as server:
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}{path}"
        finally:
            server.shutdown()
            worker.join()
