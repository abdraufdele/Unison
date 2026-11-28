"""Run typed Forge scripts and reconcile Forge transaction journals into Unison deployment v1."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from web3 import Web3, IPCProvider
from web3.exceptions import TransactionNotFound
from deployment import (
    checkSigner,
    saveJournal,
    signingEndpoint,
    validateDeploymentBindings,
    verifyConstruction,
    wire,
)
from environment import ROOT, OperatorRpc, artifact, checkNetwork, contract, endpointId, loadConfig, require

NETWORK_SCRIPTS = dict(local="DeployLocal", sepolia="DeployUnichainSepolia", mainnet="DeployUnichainMainnet")
ACTIONS = {
    "read": ("ReadAgreement", "run()"),
    "preview": ("ReadAgreement", "previewOpening()"),
    "preflightActivation": ("ReadAgreement", "preflightActivation()"),
    "verifySettlement": ("ReadAgreement", "verifySettlement()"),
    **{
        name: ("AgreementActions", name + "()") for name in ("revise", "accept", "fund", "activate", "cancel")
    },
    "approveFunding": ("AgreementActions", "approveFunding(bool)"),
    "refresh": ("FixtureOpening", "refresh()"),
    "add": ("ManagePosition", "add(int24,int24,uint128)"),
    "remove": ("ManagePosition", "remove(uint128)"),
    "rerange": ("ManagePosition", "rerange(int24,int24,uint128)"),
    **{
        name: ("SettlementActions", name + "()")
        for name in (
            "checkpoint",
            "claim",
            "terminate",
            "finalizeExpiry",
            "exitLiquidity",
            "withdrawIdle",
            "refund",
        )
    },
}


def runForge(w, c, script, sig, args, sender, env, send, directory):
    """Keep the RPC in the alias environment and save the distinct Forge journal for this invocation."""
    options = [
        "--offline",
        "--rpc-url",
        "unison_script",
        "--hardfork",
        c.get("runtimeHardfork", "cancun"),
        "--sender",
        sender,
        "--sig",
        sig,
    ]
    if sig == "claim()":
        # A later block can turn a zero payout into two ERC-20 balance writes.
        options += ["--gas-estimate-multiplier", "250"]
    if send:
        if isinstance(w.provider, IPCProvider) or c["network"] == "local":
            require(w.client_version == "anvil/v1.8.7" and sender in w.eth.accounts, "expected Anvil signer")
            options += ["--unlocked"]
        else:
            require(env.get("CONFIRM_CHAIN") == str(c["chainId"]), "explicit matching CONFIRM_CHAIN required")
            checkSigner(env.get("ACCOUNT"), sender)
            options += ["--account", env["ACCOUNT"]]
        options += ["--broadcast", "--slow"]
    require(isinstance(args, (tuple, list)), "ARGS must be a JSON array of typed arguments")
    if args:
        options += ["--", *(str(value).lower() if isinstance(value, bool) else str(value) for value in args)]
    directory.mkdir(parents=True, exist_ok=True)
    variables = dict(
        env, UNISON_SCRIPT_RPC=signingEndpoint(w), FOUNDRY_BROADCAST=str(directory / "broadcast")
    )
    # Keep encrypted wallet interaction on the user's terminal. Forge's private cache stays ignored.
    result = subprocess.run(
        ["forge", "script", script, *options],
        env=variables,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    output = result.stdout.replace(signingEndpoint(w), "[RPC]")
    (directory / "forge.log").write_text(output)
    if result.returncode:
        raise ValueError("Forge script failed: " + output[-3500:])
    return output


def forgeTransactions(w, directory, sender, required):
    """Verify mined receipts, chain inclusion, sender, nonce, destination and input against the Forge plan."""
    journals = list(directory.glob("broadcast/**/*-latest.json"))
    if not journals:
        require(not required, "missing Forge broadcast journal")
        return []
    require(len(journals) == 1, "ambiguous Forge output")
    log = json.loads(journals[0].read_text())
    require(log["chain"] == w.eth.chain_id, "Forge chain mismatch")
    receipts = {r["transactionHash"].lower(): r for r in log["receipts"]}
    rows = []
    for tx in log["transactions"]:
        h = tx.get("hash")
        if not h:
            require(not required, "incomplete Forge transaction")
            continue
        try:
            receipt = w.eth.get_transaction_receipt(h)
        except TransactionNotFound:
            require(not required, "transaction pending or missing")
            continue
        mined = w.eth.get_transaction(h)
        journalReceipt = receipts.get(h.lower())
        require(journalReceipt is not None or not required, "missing successful Forge receipt")
        plan = tx["transaction"]
        require(
            mined["from"] == sender
            and int(plan["nonce"], 16) == mined.nonce
            and (mined.to or "").lower() == (plan.get("to") or "").lower()
            and Web3.to_hex(mined.input).lower() == plan.get("input", plan.get("data", "0x")).lower()
            and (
                journalReceipt is None
                or Web3.to_hex(receipt.blockHash).lower() == journalReceipt["blockHash"].lower()
            )
            and w.eth.get_block(receipt.blockNumber).hash == receipt.blockHash,
            "transaction/receipt mismatch",
        )
        require(not required or receipt.status == 1, "reverted transaction")
        rows.append(dict(step=tx.get("function") or tx["transactionType"], receipt=wire(receipt)))
    return rows


def convertRecipe(m, recipe):
    """Import exact constructor inputs and predicted addresses without asserting they were mined."""
    a = {k: Web3.to_checksum_address(v) for k, v in recipe["addresses"].items()}
    a.update({k: Web3.to_checksum_address(recipe[k]) for k in ("adapter", "token0", "token1")})
    m.update(
        addresses=a,
        referenceSource=Web3.to_checksum_address(recipe["source"]),
        termsHash=recipe["simulatedTerms"],
        create2=dict(
            factory=a["factory"],
            address=a["hook"],
            salt=recipe["salt"],
            initHash=recipe["initHash"],
            flags="0x840",
        ),
    )
    for role, qualified in recipe["artifacts"].items():
        name = qualified.split(":")[-1]
        compiled = artifact(name)
        m["constructors"][role] = dict(
            name=name,
            source=next(iter(compiled["metadata"]["settings"]["compilationTarget"])),
            arguments=recipe["arguments"][role],
            creationKeccak=Web3.to_hex(Web3.keccak(hexstr=compiled["bytecode"]["object"])),
        )
        m["sourceKeccaks"].update({k: v["keccak256"] for k, v in compiled["metadata"]["sources"].items()})
    m["predictedRuntimeHashes"] = recipe["hashes"]


def deploy(w, c, path, env, send):
    """Reserve a fresh manifest, run the actual network entry point and verify its receipts before marking it complete."""
    path = Path(path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    directory = path.with_suffix(".forge")
    with path.open("x") as f:
        f.write('{"status":"building"}\n')
    directory.mkdir(mode=0o700)
    recipe = directory / "recipe.json"
    actor = Web3.to_checksum_address(env["UNISON_TREASURY"])
    mode = (
        "simulation"
        if not send
        else (
            "local"
            if c["network"] == "local"
            else ("fork-rehearsal" if isinstance(w.provider, IPCProvider) else "broadcast")
        )
    )
    m = dict(
        schema="unison.deployment.v1",
        workflow="forge-script",
        mode=mode,
        status="building",
        network=c["network"],
        chainId=w.eth.chain_id,
        endpointId=endpointId(dict(rpc=signingEndpoint(w))),
        fixtureAssets=c["fixtureAssets"],
        localFaultDemo=c.get("localFaultDemo", False),
        runId=env["RUN_ID"],
        treasury=actor,
        manager=Web3.to_checksum_address(env["UNISON_MANAGER"]),
        receipts=[],
        constructors={},
        sourceKeccaks={},
        addresses={},
        optimizerRuns=200,
        viaIR=True,
        evm="cancun",
        compiler=artifact("AgreementVault")["metadata"]["compiler"],
        revision=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        worktreeDirty=bool(subprocess.check_output(["git", "status", "--porcelain"])),
        forge=subprocess.check_output(["forge", "--version"], text=True).splitlines()[:2],
        dependencyPins={
            p.name: subprocess.check_output(["git", "-C", str(p), "rev-parse", "HEAD"], text=True).strip()
            for p in sorted((ROOT / "lib").iterdir())
            if (p / ".git").exists()
        },
        forkPin={k: c[k] for k in ("block", "blockHash", "coreHash") if k in c},
    )
    saveJournal(path, m)
    try:
        runForge(
            w,
            c,
            "script/deploy/" + NETWORK_SCRIPTS[c["network"]] + ".s.sol",
            "run()",
            [],
            actor,
            dict(env, UNISON_RECIPE=str(recipe)),
            send,
            directory,
        )
        convertRecipe(m, json.loads(recipe.read_text()))
        if send:
            m["receipts"] = forgeTransactions(w, directory, actor, True)
            a = m["addresses"]
            for row in m["receipts"]:
                if row["step"].startswith("install("):
                    row["step"] = "install hook"
            head = w.eth.get_block(m["receipts"][-1]["receipt"]["blockNumber"])
            m["anchor"] = dict(number=head.number, hash=head.hash.hex())
            m["runtime"] = {
                role: dict(bytes=len(code), keccak256=Web3.to_hex(Web3.keccak(code)))
                for role, addr in a.items()
                for code in [w.eth.get_code(addr, head.number)]
            }
            m["coreHash"] = m["runtime"]["core"]["keccak256"]
            vault = contract(w, "AgreementVault", a["vault"]).functions
            m["termsHash"] = Web3.to_hex(vault.termsHash().call(block_identifier=head.number))
            require(
                vault.revision().call(block_identifier=head.number) == 2
                and vault.state().call(block_identifier=head.number) == 0,
                "deployment did not finish in draft revision two",
            )
            validateDeploymentBindings(w, dict(c, rpc=signingEndpoint(w)), m)
            verifyConstruction(w, m)
            m["status"] = "complete"
        else:
            m["status"] = "simulated"
    except BaseException:
        m["status"] = "partial" if send else "failed-simulation"
        if recipe.exists() and not m["addresses"]:
            convertRecipe(m, json.loads(recipe.read_text()))
        saveJournal(path, m)
        if send:
            m["receipts"] = forgeTransactions(w, directory, actor, False)
        raise
    finally:
        saveJournal(path, m)
    return m


def invoke(w, c, path, env, action, args, send=False):
    """Select a typed script and bind its single invocation to the checked live record."""
    m = json.loads(Path(path).read_text())
    require(
        m["status"] == "complete" and m["mode"] in ("local", "broadcast", "fork-rehearsal"),
        "mined manifest required",
    )
    validateDeploymentBindings(w, dict(c, rpc=signingEndpoint(w)), m)
    if action == "verify":
        require(not send, "verification is read only")
        verifyConstruction(w, m)
        script, sig = "script/deploy/VerifyDeployment.s.sol", "run()"
    else:
        name, sig = ACTIONS[action]
        require(not send or name != "ReadAgreement", "reader is simulation only")
        script = f"script/interact/{name}.s.sol"
    actor = Web3.to_checksum_address(env.get("ACTOR") or m["treasury"])
    evidence = Path(path).resolve().with_suffix(".forge")
    evidence.mkdir(mode=0o700, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix=action + "-", dir=evidence))
    output = runForge(
        w, c, script, sig, args, actor, dict(env, MANIFEST=str(Path(path).resolve())), send, directory
    )
    if send:
        rows = forgeTransactions(w, directory, actor, True)
        require(len(rows) == 1, "expected one action receipt")
        print(action, rows[0]["receipt"]["transactionHash"], flush=True)
    return output


def main():
    mode = sys.argv[1]
    require(mode in ("deploy", "simulate", "preflight", "action", "send", "verify"), "unknown operation")
    env = os.environ.copy()
    c = loadConfig(env["NETWORK"], env["CONFIG"])
    w = Web3(OperatorRpc(c["rpc"], request_kwargs={"timeout": 30}))
    checkNetwork(w, c)
    path = Path(env["MANIFEST"])
    if mode == "preflight":
        with tempfile.TemporaryDirectory() as d:
            print(
                runForge(
                    w,
                    c,
                    "script/deploy/" + NETWORK_SCRIPTS[c["network"]] + ".s.sol",
                    "preflight()",
                    [],
                    env["UNISON_TREASURY"],
                    env,
                    False,
                    Path(d),
                )
            )
    elif mode in ("deploy", "simulate"):
        m = deploy(w, c, path, env, mode == "deploy")
        print(path, m["status"], m["runId"])
    else:
        print(
            invoke(
                w,
                c,
                path,
                env,
                "verify" if mode == "verify" else env["ACTION"],
                json.loads(env.get("ARGS", "[]")),
                mode == "send",
            )
        )


if __name__ == "__main__":
    main()
