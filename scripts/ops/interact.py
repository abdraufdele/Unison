"""Inspect one manifest, simulate a named C1 action, or explicitly send it with the correct role."""

import argparse
import fcntl
import json
from pathlib import Path

from web3 import Web3
from deployment import checkSigner, sendOperation, validateDeploymentBindings
from environment import CHAINS, checkNetwork, loadConfig, require
from lifecycle import ACTIONS, exportStatement, prepareAction, readFunction, wire
from network import confirmPublic


# Serialize sends for the same manifest and revalidate its onchain identity immediately before use.
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("command", choices=["read", "simulate", "send-local", "broadcast", "statement"])
    p.add_argument("--network", required=True, choices=CHAINS)
    p.add_argument("--config")
    p.add_argument("--manifest", required=True, type=Path)
    p.add_argument("--run-id")
    p.add_argument("--account")
    p.add_argument("--confirm-chain")
    p.add_argument("--role", choices=["treasury", "manager"], default="treasury")
    p.add_argument("--target", default="vault")
    p.add_argument("--function")
    p.add_argument("--action", choices=sorted(ACTIONS))
    p.add_argument("--terms")
    p.add_argument("--position")
    p.add_argument("--inputs", default="{}")
    p.add_argument("--args", default="[]")
    args = p.parse_args()
    c = loadConfig(args.network, args.config)
    isSend = args.command in ("broadcast", "send-local")
    if args.command == "broadcast":
        confirmPublic(c, args.account, args.confirm_chain)
    if args.command == "send-local":
        require(args.network == "local", "local send requires local manifest")
    w = Web3(Web3.HTTPProvider(c["rpc"], request_kwargs={"timeout": 30}))
    checkNetwork(w, c)
    with args.manifest.open() as f:
        if isSend:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        m = json.load(f)
        require(
            m["status"] == "complete" and m["mode"] in ("local", "broadcast"),
            "expected completed live deployment",
        )
        validateDeploymentBindings(w, c, m)
        if args.command == "read":
            result = readFunction(w, m, args.target, args.function, json.loads(args.args))
        elif args.command == "statement":
            result = exportStatement(w, c, m)
        else:
            require(args.run_id == m["runId"], "expected run ID is required")
            require(args.action in ACTIONS, "select a supported action")
            fn, sender = prepareAction(
                w, c, m, args.action, args.role, args.terms, args.position, json.loads(args.inputs)
            )
            if args.command == "simulate":
                result = {"mode": "eth_call", "from": sender, "return": wire(fn.call({"from": sender}))}
            else:
                if args.command == "broadcast":
                    checkSigner(args.account, sender)
                receipt = sendOperation(
                    w, c, fn, sender, args.account if args.command == "broadcast" else None
                )
                result = {
                    "mode": args.command,
                    "block": receipt.blockNumber,
                    "receipt": Web3.to_hex(receipt.transactionHash),
                }
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
