"""Exercise operator commands on a fresh owned Anvil, including dormant and closed lifecycle branches."""

import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
from web3 import IPCProvider, Web3
from environment import ROOT, require


# Run the public Make entry points against a single identified node and compare the exported final rights.
def exerciseLocal(port, directory, w):
    mpath = directory / "agreement.json"
    env = dict(
        os.environ,
        NETWORK="local",
        CONFIG="config/local.json",
        MANIFEST=str(mpath),
        UNISON_RPC_URL=f"http://127.0.0.1:{port}",
    )
    # Nested Make calls must use this private fixture even when the parent supplied command-line variables.
    env.pop("MAKEFLAGS", None)
    env.pop("MAKEOVERRIDES", None)
    http = Web3(Web3.HTTPProvider(env["UNISON_RPC_URL"]))
    require(
        http.eth.accounts == w.eth.accounts and http.eth.get_block(0).hash == w.eth.get_block(0).hash,
        "HTTP endpoint does not belong to this IPC fixture",
    )

    # Execute the same target and input environment used by an operator; require expected failures explicitly.
    def make(target, expectFailure=None, **values):
        result = subprocess.run(
            ["make", "-s", target], env=dict(env, **values), cwd=ROOT, text=True, capture_output=True
        )
        if expectFailure:
            require(
                result.returncode != 0 and expectFailure in result.stderr,
                f"{target} did not reject the expected condition: {result.stderr}",
            )
        elif result.returncode:
            raise RuntimeError(f"{target} failed: {result.stderr}")
        return result.stdout

    make("preflight")
    make("deploy-local")
    manifest = json.loads(mpath.read_text())
    env.update(RUN_ID=manifest["runId"], TERMS=manifest["termsHash"])
    make("bindings")
    head = w.eth.block_number
    make("rehearse")
    require(w.eth.block_number == head, "Foundry rehearsal submitted a transaction")
    make("verify", expectFailure="explorer verification requires a Sepolia deployment")
    make("deploy-local", expectFailure="File exists")
    require(w.eth.block_number == head, "duplicate deployment submitted a transaction")

    # Read a block-pinned product getter and return its lossless JSON value.
    def read(function, target="vault", args=None):
        return json.loads(make("read", TARGET=target, FUNCTION=function, ARGS=json.dumps(args or [])))[
            "value"
        ]

    # Send only named actions using current manifest, reviewed terms and the selected fixed role.
    def act(action, role="treasury", **values):
        return make("act-local", ACTION=action, ROLE=role, **values)

    # Time and snapshot controls never leave the owned IPC socket and require the active run's onchain marker.
    def localControl(method, params):
        require(read("agreementId") == env["RUN_ID"] and w.eth.chain_id == 31337, "wrong local run")
        response = w.provider.make_request(method, params)
        require("result" in response and response["result"] is not False, "local control failed")
        return response["result"]

    draft = read("currentTerms")
    require(draft["agreementId"] == env["RUN_ID"] and draft["treasuryRecipient"] == manifest["treasury"],
            "terms inspection returned a different agreement")
    require(read("decimals", "token0") == "6" and read("decimals", "token1") == "6", "token scale")
    make("simulate", ACTION="accept", RUN_ID="0x" + "00" * 32, expectFailure="expected run ID is required")
    make("simulate", ACTION="accept", TERMS="0x" + "00" * 32, expectFailure="expected terms hash no longer current")
    make("simulate", ACTION="credit", expectFailure="invalid choice")
    require(w.eth.block_number == head, "rejection or rehearsal wrote chain state")
    refs = json.dumps(dict.fromkeys(("adapter", "source"), manifest["addresses"]["adapter"]))
    act("revise", INPUTS=refs)
    env["TERMS"] = read("termsHash")
    require(env["TERMS"] != manifest["termsHash"], "revision did not invalidate consent")
    act("accept")
    act("accept", "manager")
    act("approveA")
    act("approveB")
    act("fund")
    funded = localControl("evm_snapshot", [])
    act("cancel")
    act("refund")
    act("withdrawIdle")
    require(read("refunded", "escrow") == "100000000", "funded cancellation")
    localControl("evm_revert", [funded])
    act("publishOpening")
    read("previewOpeningReference")
    read("preflightActivation", args=[env["TERMS"]])
    act("activate")
    qualification = read("qualification", "hook")
    require(qualification["qualified"] is True and qualification["failures"] == "0", "installed seed did not qualify")
    require(read("positionPoolId") == read("poolId", "hook"), "vault and hook identify different pools")
    active = localControl("evm_snapshot", [])
    localControl("evm_increaseTime", [301])
    localControl("evm_mine", [])
    act("finalizeExpiry", "manager")
    require(read("effectiveStop") == read("scheduledEnd"), "expiry clipping")
    localControl("evm_revert", [active])
    for action, delta, edge in (
        ("add", 1_000_000, 120),
        ("remove", 1_000_000, 120),
        ("rerange", 100_000_000_000, 180),
    ):
        localControl("evm_increaseTime", [31])
        localControl("evm_mine", [])
        position = read("positionId")
        bounds = dict(
            ttl=30,
            tickLower=-1,
            tickUpper=1,
            maxInput0=900000000,
            maxInput1=900000000,
            minOutput0=0,
            minOutput1=0,
            liquidity=delta,
        )
        if action != "remove":
            bounds.update(lower=-edge, upper=edge)
        values = dict(ACTION=action, POSITION=position, INPUTS=json.dumps(bounds))
        make("simulate", ROLE="treasury", expectFailure="unsupported action or actor role", **values)
        stale = dict(values, POSITION="0x" + "11" * 32)
        make("simulate", ROLE="manager", expectFailure="expected position no longer current", **stale)
        make("simulate", ROLE="manager", **values)
        make("act-local", ROLE="manager", **values)
    act("checkpoint")
    act("claim", "manager")
    act("terminate")
    act("exitLiquidity")
    act("withdrawIdle")
    act("refund")
    act("claim", "manager")
    for getter in ("claimable", "refundable", "reserved"):
        require(read(getter, "escrow") == "0", f"terminal {getter} outstanding")
    head = w.eth.block_number
    statement = json.loads(make("statement"))
    require(statement["reconciliation"] == "matched" and w.eth.block_number == head, "statement mismatch")
    rights = statement["derived"]
    print(f"Verified local C1 run {env['RUN_ID']} through block {head}: {json.dumps(rights)}", flush=True)


# Start a random-account loopback node, cross-check its private IPC, and terminate that child on every exit.
def main():
    with tempfile.TemporaryDirectory(prefix="unison-actions-") as temp:
        directory = Path(temp)
        ipc = directory / "run.ipc"
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        cmd = ["make", "-s", "local-node", f"PORT={port}", f"IPC={ipc}"]
        with subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, start_new_session=True) as node:
            try:
                w = Web3(IPCProvider(str(ipc)))
                for _ in range(100):
                    if ipc.exists() and w.is_connected():
                        break
                    require(node.poll() is None, "local node exited")
                    time.sleep(0.1)
                exerciseLocal(port, directory, w)
            finally:
                if node.poll() is None:
                    os.killpg(node.pid, signal.SIGTERM)
                node.wait(timeout=10)


if __name__ == "__main__":
    main()
