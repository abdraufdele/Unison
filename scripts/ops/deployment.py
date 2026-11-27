"""Direct treasury deployment with a receipt journal and a dedicated CREATE2 hook factory."""

import json
import os
import secrets
import subprocess
from pathlib import Path

from hexbytes import HexBytes
import rlp
from web3 import Web3, IPCProvider
from environment import PRODUCT, artifact, contract, endpointId, require, verifyRuntime


# Replace the current journal atomically after each receipt or intent.
def saveJournal(path, data):
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("x") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    temp.replace(path)


# Convert receipt hashes and logs to JSON values using Web3's canonical wire encoder.
def wire(data):
    return json.loads(Web3.to_json(data))


# Resolve the signer transport from the active Web3 instance, including the simulated chain's own socket.
def signingEndpoint(w):
    if isinstance(w.provider, IPCProvider):
        return str(w.provider.ipc_path)
    require(isinstance(w.provider, Web3.HTTPProvider), "unsupported signer transport")
    return w.provider.endpoint_uri


# Rehearse the treasury CREATE with Foundry on the same endpoint. No script broadcast flag is used.
def rehearseVault(w, c, treasury, arguments):
    env = dict(
        os.environ,
        UNISON_SCRIPT_RPC=signingEndpoint(w),
        UNISON_CHAIN_ID=str(c["chainId"]),
        UNISON_TREASURY=treasury,
        UNISON_VAULT_ARGS=arguments,
    )
    subprocess.run(
        [
            "forge",
            "script",
            "script/CreateVault.s.sol:CreateVaultScript",
            "--offline",
            "--rpc-url",
            "unison_script",
            "--hardfork",
            c.get("runtimeHardfork", "cancun"),
            "--sender",
            treasury,
            "--non-interactive",
        ],
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )


# Use the current pending nonce and an exact compiled constructor or function call.
def sendOperation(w, c, fn, sender, account=None, onSubmitted=None):
    require(w.eth.chain_id == c["chainId"], "chain changed before send")
    nonce = w.eth.get_transaction_count(sender, "pending")
    create = hasattr(fn, "data_in_transaction")
    tx = {
        "from": sender,
        "nonce": nonce,
        "data": fn.data_in_transaction if create else fn._encode_transaction_data(),
    }
    if not create:
        tx["to"] = fn.address
    w.eth.call(tx)
    if account:
        env = dict(os.environ, ETH_RPC_URL=signingEndpoint(w))
        args = [
            "cast",
            "send",
            "--async",
            "--account",
            account,
            "--from",
            sender,
            "--nonce",
            str(nonce),
            "--chain",
            str(c["chainId"]),
        ]
        args += ["--create", tx["data"]] if create else [tx["to"], "--data", tx["data"]]
        # A failing RPC transport can include its credential-bearing URL in cast's stderr.
        try:
            txHash = subprocess.check_output(args, env=env, text=True, stderr=subprocess.PIPE).strip()
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(f"Cast submission failed (exit {exc.returncode}). Inspect the journal before retrying.") from None
    else:
        require(
            w.client_version == "anvil/v1.8.7" and sender in w.eth.accounts, "expected owned Anvil account"
        )
        txHash = w.eth.send_transaction(tx)
    if onSubmitted:
        onSubmitted(Web3.to_hex(HexBytes(txHash)), nonce)
    receipt = w.eth.wait_for_transaction_receipt(txHash, timeout=120)
    require(receipt.status == 1, f"transaction reverted: {Web3.to_hex(receipt.transactionHash)}")
    actual = w.eth.get_transaction(txHash)
    require(
        actual["from"] == sender
        and actual.nonce == nonce
        and actual.input == Web3.to_bytes(hexstr=tx["data"])
        and actual.to == tx.get("to"),
        "mined transaction differs from prepared operation",
    )
    return receipt


# Read the encrypted Foundry account's public address and compare with the configured role.
def checkSigner(account, expected):
    require(account, "set ACCOUNT to a Foundry keystore name")
    address = subprocess.check_output(["cast", "wallet", "address", "--account", account], text=True).strip()
    require(Web3.to_checksum_address(address) == expected, "keystore does not match the named actor")


# Mine the two C1 callback flags using this factory, this vault and this exact creation bytecode.
def mineHook(factory, init):
    initHash = Web3.keccak(hexstr=init)
    prefix = b"\xff" + bytes.fromhex(factory[2:])
    for candidate in range(1_000_000):
        salt = candidate.to_bytes(32, "big")
        digest = Web3.keccak(prefix + salt + initHash)
        if int.from_bytes(digest[-2:], "big") & 0x3FFF == 0x840:
            return salt, Web3.to_checksum_address(digest[-20:]), Web3.to_hex(initHash)
    raise RuntimeError("CREATE2 search exhausted")


# Resolve only supported artifact roles, preserving the original v1 fixture records.
def deploymentArtifacts(m):
    names = dict(PRODUCT)
    if m.get("workflow") == "forge-script":
        for role in ("token0", "token1", "adapter"):
            names.pop(role)
        if m["fixtureAssets"]:
            fault = m.get("localFaultDemo", False)
            require(not fault or m["network"] == "local", "fault injector outside local chain")
            require(m["network"] != "mainnet", "mainnet fixture assets")
            names.update(token0="CustodyToken" if fault else "DemoToken",
                         token1="CustodyToken" if fault else "DemoToken", adapter="DemoReference")
    return names


# Verify deployment identity, immutable getters, runtime and vault/hook/escrow/quote bindings before use.
def validateDeploymentBindings(w, c, m):
    require(
        m["schema"] == "unison.deployment.v1"
        and m["chainId"] == w.eth.chain_id == c["chainId"]
        and m["network"] == c["network"]
        and m["endpointId"] == endpointId(c),
        "manifest network mismatch",
    )
    require(
        w.eth.get_block(m["anchor"]["number"]).hash.hex() == m["anchor"]["hash"], "manifest anchor mismatch"
    )
    a = m["addresses"]
    plan = m["create2"]
    require(plan["factory"] == a["factory"] and plan["address"] == a["hook"] and plan["flags"] == "0x840",
            "recorded hook plan mismatch")
    for role, name in deploymentArtifacts(m).items():
        verifyRuntime(w, name, a[role])
    require(Web3.to_hex(Web3.keccak(w.eth.get_code(a["core"]))) == m["coreHash"], "core identity mismatch")
    if c["network"] == "local":
        verifyRuntime(w, "PoolManager", a["core"])
    else:
        require(
            a["core"].lower() == c["core"].lower() and m["coreHash"] == c["coreHash"], "wrong official core"
        )
    init = (
        contract(w, "ServiceHook")
        .constructor(a["vault"], a["core"], a["token0"], a["token1"])
        .data_in_transaction
    )
    initHash = Web3.keccak(hexstr=init)
    mined = Web3.keccak(
        b"\xff" + bytes.fromhex(a["factory"][2:]) + Web3.to_bytes(hexstr=m["create2"]["salt"]) + initHash
    )
    require(
        a["hook"] == Web3.to_checksum_address(mined[-20:])
        and Web3.to_hex(initHash) == m["create2"]["initHash"],
        "CREATE2 identity mismatch",
    )
    v = contract(w, "AgreementVault", a["vault"]).functions
    h = contract(w, "ServiceHook", a["hook"]).functions
    e = contract(w, "CompensationEscrow", a["escrow"]).functions
    terms = v.currentTerms().call()
    require(
        terms.chainId == w.eth.chain_id
        and terms.activationCutoff == terms.createdAt + 86400
        and terms.vault == a["vault"]
        and Web3.to_hex(terms.agreementId) == m["runId"]
        and terms.treasury == terms.treasuryRecipient == m["treasury"]
        and terms.manager == terms.managerRecipient == m["manager"],
        "parties or agreement mismatch",
    )
    require(
        list(terms.bindings[:5]) == [a[x] for x in ("core", "token0", "token1", "hook", "escrow")]
        and (m.get("workflow") == "forge-script" or terms.bindings.referenceSource == terms.bindings.referenceAdapter),
        "terms bindings differ from manifest",
    )
    if m.get("workflow") == "forge-script":
        if terms.revision == 2:
            require(terms.bindings.referenceAdapter == a["adapter"]
                    and terms.bindings.referenceSource == m["referenceSource"]
                    and Web3.to_hex(v.termsHash().call()) == m["termsHash"], "initial reference or terms mismatch")
        if not m["fixtureAssets"]:
            for role in ("token0", "token1", "adapter", "source"):
                addr = a[role] if role != "source" else m["referenceSource"]
                require(addr == Web3.to_checksum_address(c[role]) and
                        Web3.to_hex(Web3.keccak(w.eth.get_code(addr))) == c[role + "Hash"], "external dependency mismatch")
    else:
        verifyRuntime(w, "MockOpeningReferenceAdapter", terms.bindings.referenceAdapter)
    require(
        h.vault().call() == a["vault"]
        and h.poolManager().call() == a["core"]
        and e.vault().call() == a["vault"]
        and e.managerRecipient().call() == m["manager"]
        and e.treasuryRecipient().call() == m["treasury"]
        and e.paymentToken().call() == a["token1"],
        "custody mismatch",
    )
    key = (a["token0"], a["token1"], 3000, 60, a["hook"])
    pool = Web3.keccak(w.codec.encode(["address", "address", "uint24", "int24", "address"], key))
    require(h.poolId().call() == pool and int(a["hook"], 16) & 0x3FFF == 0x840, "hook pool or mask mismatch")
    for role in ("token0", "token1"):
        require(contract(w, "CustodyToken", a[role]).functions.decimals().call() == 6, "wrong token scale")
    require(int(a["token0"], 16) < int(a["token1"], 16), "token ordering mismatch")
    for role, address in a.items():
        require(
            Web3.to_hex(Web3.keccak(w.eth.get_code(address))) == m["runtime"][role]["keccak256"],
            "runtime changed",
        )


# Verify historical CREATE inputs and the authenticated factory install against their canonical receipts.
def verifyConstruction(w, m):
    addresses = m["addresses"]
    names = deploymentArtifacts(m)
    if m["network"] == "local":
        names["core"] = "PoolManager"
    require(set(names) == set(m["constructors"]), "constructor inventory mismatch")
    direct = {
        row["receipt"]["contractAddress"]: row["receipt"]
        for row in m["receipts"]
        if row["receipt"]["contractAddress"]
    }
    for role, name in names.items():
        record = m["constructors"][role]
        compiled = artifact(name)
        source = next(iter(compiled["metadata"]["settings"]["compilationTarget"]))
        code = compiled["bytecode"]["object"]
        require(
            record["name"] == name
            and record["source"] == source
            and record["creationKeccak"] == Web3.to_hex(Web3.keccak(hexstr=code)),
            "creation artifact mismatch",
        )
        if role in ("hook", "quote"):
            continue
        r = direct[addresses[role]]
        actual = w.eth.get_transaction_receipt(r["transactionHash"])
        require(
            actual.status == 1
            and actual.contractAddress == addresses[role]
            and Web3.to_hex(actual.blockHash) == r["blockHash"],
            "CREATE receipt mismatch",
        )
        tx = w.eth.get_transaction(r["transactionHash"])
        require(
            tx["from"] == m["treasury"]
            and tx.to is None
            and Web3.to_hex(tx.input) == code + record["arguments"][2:],
            "creator or constructor mismatch",
        )
    args = [addresses[k] for k in ("vault", "core", "token0", "token1")]
    hookArgs = w.codec.encode(["address"] * 4, args)
    require(m["constructors"]["hook"]["arguments"] == Web3.to_hex(hookArgs), "hook constructor mismatch")
    require(
        m["constructors"]["quote"]["arguments"] == "0x"
        and addresses["quote"]
        == Web3.to_checksum_address(
            Web3.keccak(rlp.encode([bytes.fromhex(addresses["vault"][2:]), 1]))[-20:]
        ),
        "constructor-created helper mismatch",
    )
    (install,) = [r["receipt"] for r in m["receipts"] if r["step"] == "install hook"]
    tx = w.eth.get_transaction(install["transactionHash"])
    receipt = w.eth.get_transaction_receipt(tx.hash)
    salt = Web3.to_bytes(hexstr=m["create2"]["salt"])
    installFn = contract(w, "HookInstaller", addresses["factory"]).functions.install(salt, *args)
    require(
        tx["from"] == m["treasury"]
        and tx.to == addresses["factory"]
        and receipt.status == 1
        and Web3.to_hex(tx.input) == installFn._encode_transaction_data(),
        "factory transaction mismatch",
    )


# Deploy a draft from the treasury, then bind actual child addresses in a new unaccepted revision.
def deployAgreement(w, c, path, mode, account=None):
    forkOnly = mode == "fork-rehearsal" and isinstance(w.provider, IPCProvider)
    require(
        forkOnly or (c["network"] != "mainnet" and c["fixtureAssets"] is True),
        "mainnet C1 requires a vetted exact-transfer pair and an approved fresh opening reference",
    )
    simulated = mode in ("simulation", "fork-rehearsal")
    if simulated or c["network"] == "local":
        treasury, manager = w.eth.accounts[:2]
        if not forkOnly and (c.get("treasury") or c.get("manager")):
            treasury, manager = (Web3.to_checksum_address(c[k]) for k in ("treasury", "manager"))
    else:
        treasury, manager = (Web3.to_checksum_address(c[k]) for k in ("treasury", "manager"))
    require(treasury != manager and int(treasury, 16) and int(manager, 16), "missing distinct signer roles")
    if account:
        checkSigner(account, treasury)
    else:
        require(treasury in w.eth.accounts, "dry run needs a local signer or the matching keystore")
    require(not simulated or isinstance(w.provider, IPCProvider), "simulations require owned IPC")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation refuses to overwrite completed and interrupted deployments alike.
    with path.open("x") as f:
        f.write("{}\n")
    a = {}
    marker = secrets.token_bytes(32)
    m = {
        "schema": "unison.deployment.v1",
        "mode": mode,
        "network": c["network"],
        "chainId": w.eth.chain_id,
        "endpointId": endpointId(c),
        "runId": Web3.to_hex(marker),
        "treasury": treasury,
        "manager": manager,
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "forge": subprocess.check_output(["forge", "--version"], text=True).splitlines()[:2],
        "compiler": artifact("AgreementVault")["metadata"]["compiler"],
        "optimizerRuns": 200,
        "viaIR": True,
        "evm": "cancun",
        "addresses": a,
        "receipts": [],
        "constructors": {},
        "status": "building",
    }
    m["worktreeDirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"]))
    m["sourceKeccaks"] = {
        source: info["keccak256"]
        for name in set(PRODUCT.values()) | {"PoolManager"}
        for source, info in artifact(name)["metadata"]["sources"].items()
    }
    core = "lib/v4-core"
    m["dependencyPins"] = {
        name: subprocess.check_output(["git", "-C", path, "rev-parse", "HEAD"], text=True).strip()
        for name, path in (("v4-core", core), ("solmate", "lib/solmate"))
    }
    m["forkPin"] = {k: c[k] for k in ("block", "blockHash", "coreHash") if k in c}
    saveJournal(path, m)

    # Persist the exact operation label before sending so a partial run cannot silently restart.
    def submit(label, fn):
        m["pending"] = {"step": label}
        saveJournal(path, m)

        # Journal the submitted hash before waiting so a timeout leaves an identifiable transaction.
        def recordSubmission(txHash, nonce):
            m["pending"].update(transactionHash=txHash, nonce=nonce)
            saveJournal(path, m)

        receipt = sendOperation(w, c, fn, treasury, account, recordSubmission)
        m["receipts"].append({"step": label, "receipt": wire(receipt)})
        del m["pending"]
        saveJournal(path, m)
        return receipt

    # Obtain each CREATE address from the mined treasury receipt before building dependent constructors.
    def create(role, name, *args):
        builder = contract(w, name).constructor(*args)
        recordConstructor(role, name, builder)
        if role == "vault" and c["network"] != "mainnet":
            rehearseVault(w, c, treasury, m["constructors"][role]["arguments"])
        address = submit("create " + role, builder).contractAddress
        verifyRuntime(w, name, address)
        a[role] = address
        return address

    # Retain constructor ABI bytes and creation identity for explorer verification and offline review.
    def recordConstructor(role, name, builder):
        code = artifact(name)["bytecode"]["object"]
        require(len(Web3.to_bytes(hexstr=builder.data_in_transaction)) <= 49152, "init code exceeds EIP-3860")
        m["constructors"][role] = {
            "name": name,
            "source": next(iter(artifact(name)["metadata"]["settings"]["compilationTarget"])),
            "arguments": "0x" + builder.data_in_transaction[len(code) :],
            "creationKeccak": Web3.to_hex(Web3.keccak(hexstr=code)),
        }

    if c["network"] == "local":
        create("core", "PoolManager", treasury)
    else:
        a["core"] = Web3.to_checksum_address(c["core"])
    first = create("first", "CustodyToken")
    second = create("second", "CustodyToken")
    a["token0"], a["token1"] = sorted((first, second), key=lambda x: int(x, 16))
    for role in ("token0", "token1"):
        m["constructors"][role] = m["constructors"].pop("first" if a[role] == first else "second")
    del a["first"], a["second"]
    create("adapter", "MockOpeningReferenceAdapter")
    create("factory", "HookInstaller")
    # Draft placeholders are distinct, empty and never accepted. Revision two binds actual deployed contracts.
    temporary = [Web3.to_checksum_address(Web3.keccak(marker + bytes([i]))[-20:]) for i in (0, 1)]
    require(all(not w.eth.get_code(x) for x in temporary), "draft placeholder already has code")
    prefix = [a["core"], a["token0"], a["token1"]]
    refs = [a["adapter"], a["adapter"]]
    create("vault", "AgreementVault", marker, manager, prefix + temporary + refs)
    a["quote"] = Web3.to_checksum_address(Web3.keccak(rlp.encode([bytes.fromhex(a["vault"][2:]), 1]))[-20:])
    recordConstructor("quote", "OpeningQuote", contract(w, "OpeningQuote").constructor())
    create("escrow", "CompensationEscrow", a["vault"], a["token1"], treasury, manager)
    args = [a["vault"], *prefix]
    init = contract(w, "ServiceHook").constructor(*args)
    salt, hook, initHash = mineHook(a["factory"], init.data_in_transaction)
    require(not w.eth.get_code(hook), "mined hook address already occupied")
    recordConstructor("hook", "ServiceHook", init)
    m["create2"] = {
        "factory": a["factory"],
        "salt": Web3.to_hex(salt),
        "initHash": initHash,
        "address": hook,
        "flags": "0x840",
    }
    submit("install hook", contract(w, "HookInstaller", a["factory"]).functions.install(salt, *args))
    a["hook"] = hook
    vault = contract(w, "AgreementVault", a["vault"])
    submit("bind actual custody", vault.functions.revise(prefix + [hook, a["escrow"]] + refs))
    key = (a["token0"], a["token1"], 3000, 60, hook)
    submit("initialize mock pair", contract(w, "PoolManager", a["core"]).functions.initialize(key, 1 << 96))
    for role, amount in (("token0", 2_000_000_000), ("token1", 2_100_000_000)):
        submit("mint fixture " + role, contract(w, "CustodyToken", a[role]).functions.mint(treasury, amount))
    block = w.eth.get_block("latest")
    m["anchor"] = {"number": block.number, "hash": block.hash.hex()}
    m["runtime"] = {
        k: {"bytes": len(w.eth.get_code(v)), "keccak256": Web3.to_hex(Web3.keccak(w.eth.get_code(v)))}
        for k, v in a.items()
    }
    m["coreHash"] = m["runtime"]["core"]["keccak256"]
    m["termsHash"] = Web3.to_hex(vault.functions.termsHash().call())
    validateDeploymentBindings(w, c, m)
    verifyConstruction(w, m)
    m["status"] = "complete"
    saveJournal(path, m)
    return m
