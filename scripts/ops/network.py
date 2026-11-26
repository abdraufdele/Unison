"""Run C1 network checks, mine and simulate a deployment, or explicitly publish a reviewed Sepolia draft."""

import argparse
import os
import subprocess
from pathlib import Path
import json
from web3 import Web3
from environment import CHAINS, CORE, checkNetwork, loadConfig, ownedChain, require
from deployment import deployAgreement, signingEndpoint, validateDeploymentBindings, verifyConstruction


# Require the intended chain and a verified keystore before entering a public submission path.
def confirmPublic(c, account, confirmation):
    require(
        c["network"] == "sepolia" and confirmation == str(c["chainId"]) and account,
        "public submission requires a Sepolia config, matching chain confirmation and Foundry ACCOUNT",
    )


# Resolve the deployment mode before opening any wallet or constructing a transaction.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=["preflight", "fork", "dry-run", "local", "broadcast", "bindings", "verify", "rehearse"],
    )
    parser.add_argument("--network", choices=CHAINS, required=True)
    parser.add_argument("--config")
    parser.add_argument("--manifest")
    parser.add_argument("--account")
    parser.add_argument("--confirm-chain")
    args = parser.parse_args()
    c = loadConfig(args.network, args.config)
    live = Web3(Web3.HTTPProvider(c["rpc"], request_kwargs={"timeout": 30}))
    if args.command == "broadcast":
        confirmPublic(c, args.account, args.confirm_chain)
    if args.command == "local":
        require(c["network"] == "local", "local deployment requires loopback and chain 31337")
    if args.command in ("broadcast", "dry-run", "local"):
        require(
            c["network"] != "mainnet" and c["fixtureAssets"] is True,
            "no approved exact-transfer mainnet token pair or suitable C1 opening reference",
        )
    if args.command not in ("fork", "preflight"):
        require(args.manifest, "provide a manifest path")
    if not (args.command == "dry-run" and c["network"] == "local"):
        checkNetwork(live, c)
    if args.command == "preflight":
        print(f"Verified {args.network} chain {c['chainId']} at {c.get('block', 'local head')}")
    elif args.command == "fork":
        require(c["network"] in CORE, "select sepolia or mainnet for a pinned fork")
        with ownedChain(c) as w:
            checkNetwork(w, c)
            # All fixture assets and calls exist only in this owned fork, including on a mainnet fork.
            from rehearsal import exerciseFork

            exerciseFork(w, c)
    elif args.command in ("bindings", "verify", "rehearse"):
        m = json.loads(Path(args.manifest).read_text())
        require(
            m["status"] == "complete" and m["mode"] in ("local", "broadcast"),
            "expected a completed live manifest",
        )
        validateDeploymentBindings(live, c, m)
        verifyConstruction(live, m)
        if args.command == "rehearse":
            env = dict(
                os.environ,
                UNISON_SCRIPT_RPC=signingEndpoint(live),
                UNISON_CHAIN_ID=str(c["chainId"]),
                UNISON_VAULT=m["addresses"]["vault"],
                UNISON_RUN_ID=m["runId"],
                UNISON_TERMS=m["termsHash"],
            )
            subprocess.run(
                [
                    "forge",
                    "script",
                    "script/RehearseAgreement.s.sol:RehearseAgreementScript",
                    "--offline",
                    "--rpc-url",
                    "unison_script",
                    "--non-interactive",
                ],
                env=env,
                check=True,
            )
        if args.command == "verify":
            require(c["network"] == "sepolia", "explorer verification requires a Sepolia deployment")
            for role, record in m["constructors"].items():
                subprocess.run(
                    [
                        "forge",
                        "verify-contract",
                        "--chain",
                        str(c["chainId"]),
                        "--watch",
                        "--constructor-args",
                        record["arguments"],
                        m["addresses"][role],
                        record["source"] + ":" + record["name"],
                    ],
                    check=True,
                )
        print("Verified deployed bindings")
    elif args.command == "dry-run":
        with ownedChain(c) as w:
            if c["network"] != "local":
                checkNetwork(w, c)
            m = deployAgreement(w, c, args.manifest, "simulation", args.account)
            print(f"Simulation completed for {m['runId']}")
    else:
        m = deployAgreement(live, c, args.manifest, args.command, args.account)
        print(f"Draft {m['runId']} at {m['addresses']['vault']}")


if __name__ == "__main__":
    main()
