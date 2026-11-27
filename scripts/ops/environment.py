"""Pinned deployment inputs, owned fork sessions and compiled runtime checks."""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager, ExitStack
from pathlib import Path
from urllib.parse import urlsplit

from web3 import Web3, IPCProvider
from forkReads import forkReads

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "experiments/m6"))
from run import artifact, SOURCES

# Include the private constructor-created helper in the existing artifact verifier.
SOURCES["OpeningQuote"] = "OpeningQuote"

CHAINS = {"local": 31337, "sepolia": 1301, "mainnet": 130}
PRODUCT = {
    "vault": "AgreementVault",
    "hook": "ServiceHook",
    "escrow": "CompensationEscrow",
    "quote": "OpeningQuote",
    "adapter": "MockOpeningReferenceAdapter",
    "factory": "HookInstaller",
    "token0": "CustodyToken",
    "token1": "CustodyToken",
}
CORE = {
    "sepolia": "0x00b036b58a818b1bc34d502d3fe730db729e62ac",
    "mainnet": "0x1f98400000000000000000000000000000000004",
}


# Abort with an actionable input error even when Python runs with optimization enabled.
def require(condition, message):
    if not condition:
        raise ValueError(message)


# Bind operator inputs to the selected network and keep credential-bearing RPC URLs out of manifests.
def loadConfig(network, path):
    require(__debug__, "source verification requires Python assertions enabled")
    config = json.loads(Path(path or ROOT / f"config/{network}.json").read_text())
    require(config["network"] == network and config["chainId"] == CHAINS[network], "network/config mismatch")
    require(config.get("fixtureAssets") is (network != "mainnet"), "invalid C1 mock policy for network")
    config["rpc"] = os.environ.get("UNISON_RPC_URL") or config["rpc"]
    url = urlsplit(config["rpc"])
    if network == "local":
        require(
            url.scheme == "http"
            and url.hostname == "127.0.0.1"
            and not url.username
            and not url.password
            and not url.query
            and url.path in ("", "/"),
            "expected a loopback Anvil endpoint",
        )
    else:
        require(
            url.scheme == "https" and config["core"].lower() == CORE[network], "public endpoint/core mismatch"
        )
        require(config["runtimeHardfork"] == "optimism:karst", "unsupported runtime for this fork pin")
        require(
            config["block"] > 0 and len(Web3.to_bytes(hexstr=config["blockHash"])) == 32, "missing fork pin"
        )
    return config


# Return the exact compiled factory or an ABI-bound instance at a checksummed address.
def contract(w, name, address=None):
    data = artifact(name)
    return w.eth.contract(
        address=Web3.to_checksum_address(address) if address else None,
        abi=data["abi"],
        bytecode=data["bytecode"]["object"],
        decode_tuples=True,
    )


# Compare compiler runtime bytes except immutable slots whose concrete values are checked through getters.
def verifyRuntime(w, name, address):
    data = artifact(name)["deployedBytecode"]
    expected = bytearray.fromhex(data["object"][2:])
    actual = bytearray(w.eth.get_code(address))
    require(0 < len(actual) == len(expected) <= 24576, f"{name} runtime size mismatch")
    for slots in data.get("immutableReferences", {}).values():
        for slot in slots:
            start, length = slot["start"], slot["length"]
            actual[start : start + length] = expected[start : start + length]
    require(actual == expected, f"{name} runtime differs from the compiled artifact")


# Confirm the pinned header, deployed core runtime and one actual external storage read.
def checkNetwork(w, c):
    require(w.eth.chain_id == c["chainId"], "RPC chain ID mismatch")
    if c["network"] == "local":
        require(w.client_version == "anvil/v1.8.7", "expected pinned local Anvil")
        return
    n, address = c["block"], Web3.to_checksum_address(c["core"])
    require(w.eth.get_block(n).hash == Web3.to_bytes(hexstr=c["blockHash"]), "pinned block mismatch")
    code = w.eth.get_code(address, n)
    require(code and Web3.to_hex(Web3.keccak(code)) == c["coreHash"], "deployed core runtime mismatch")
    require(w.eth.get_code(address) == code, "core runtime changed since configured pin")
    call = Web3.keccak(text="extsload(bytes32)")[:4] + bytes(32)
    require(len(w.eth.call({"to": address, "data": call}, n)) == 32, "core extsload unavailable")


# Hash the endpoint string without persisting API keys or provider credentials.
def endpointId(c):
    return hashlib.sha256(c["rpc"].encode()).hexdigest()


# Start an isolated Anvil node and use only its temporary IPC socket for simulated transactions.
@contextmanager
def ownedChain(c):
    with tempfile.TemporaryDirectory(prefix="unison-ops-") as directory, ExitStack() as sessions:
        ipc = Path(directory) / "node.ipc"
        args = [
            "anvil",
            "--port",
            "0",
            "--host",
            "127.0.0.1",
            "--quiet",
            "--no-cors",
            "--mnemonic-random",
            "12",
            "--ipc",
            str(ipc),
            "--chain-id",
            str(c["chainId"]),
            "--hardfork",
            c.get("runtimeHardfork", "cancun"),
        ]
        env = os.environ.copy()
        if c["network"] != "local":
            args += [
                "--network",
                "optimism",
                "--fork-url",
                sessions.enter_context(forkReads(c["rpc"])),
                "--fork-block-number",
                str(c["block"]),
                "--fork-state-by-number",
                "--fork-retry-backoff",
                "1000",
                "--compute-units-per-second",
                "100",
            ]
        with subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env) as node:
            try:
                w = Web3(IPCProvider(str(ipc), timeout=45))
                for _ in range(900):
                    if ipc.exists() and w.is_connected():
                        break
                    require(node.poll() is None, "owned fork failed to start; check archive RPC availability")
                    time.sleep(0.1)
                require(w.is_connected() and w.eth.chain_id == c["chainId"], "owned Anvil IPC unavailable")
                yield w
            finally:
                node.terminate()
                try:
                    node.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    node.kill()
                    node.wait()
