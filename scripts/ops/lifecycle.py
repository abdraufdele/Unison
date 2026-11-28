"""Fixed C1 actions and ABI-filtered, block-pinned reads."""

import sys
from types import SimpleNamespace
from web3 import Web3
from environment import ROOT, PRODUCT, contract, require, verifyRuntime
from deployment import deploymentArtifacts, validateDeploymentBindings

sys.path.insert(0, str(ROOT / "scripts/viewer"))
from statement import statement, wire
from artifacts import buildId

PARTIES = {
    "accept": ("treasury", "manager"),
    "revise": ("treasury",),
    "approveA": ("treasury",),
    "approveB": ("treasury",),
    "fund": ("treasury",),
    "activate": ("treasury",),
    "add": ("manager",),
    "remove": ("manager",),
    "rerange": ("manager",),
    "terminate": ("treasury",),
    "exitLiquidity": ("treasury",),
    "withdrawIdle": ("treasury",),
    "publishOpening": ("treasury",),
}
BOTH = ("treasury", "manager")
ACTIONS = set(PARTIES) | {"cancel", "claim", "refund", "finalizeExpiry", "checkpoint"}


# Validate the deployment and action envelope before constructing a whitelisted ABI call.
def prepareAction(w, c, m, action, role, termsHash, position, inputs):
    require(action in ACTIONS and role in PARTIES.get(action, BOTH), "unsupported action or actor role")
    a = m["addresses"]
    sender = m[role]
    vault = contract(w, "AgreementVault", a["vault"]).functions
    terms = vault.currentTerms().call()
    current = vault.termsHash().call()
    require(termsHash == Web3.to_hex(current), "expected terms hash no longer current")
    now = w.eth.get_block("latest").timestamp
    if action in ("add", "remove", "rerange"):
        currentId = vault.positionId().call()
        require(Web3.to_hex(currentId) == position, "expected position no longer current")
        required = {
            "ttl",
            "tickLower",
            "tickUpper",
            "maxInput0",
            "maxInput1",
            "minOutput0",
            "minOutput1",
            "liquidity",
        }
        if action != "remove":
            required |= {"lower", "upper"}
        require(
            set(inputs) == required and all(type(v) is int for v in inputs.values()),
            "invalid adjustment inputs",
        )
        require(
            0 < inputs["ttl"] <= terms.parameters.maxExecutionWindow and inputs["liquidity"] > 0,
            "invalid TTL/L",
        )
        bounds = (
            current,
            now,
            now + inputs["ttl"],
            *(
                inputs[k]
                for k in ("tickLower", "tickUpper", "maxInput0", "maxInput1", "minOutput0", "minOutput1")
            ),
        )
        args = [currentId]
        if action != "remove":
            args.extend([inputs["lower"], inputs["upper"]])
        return getattr(vault, action)(*args, inputs["liquidity"], bounds), sender
    if action == "revise":
        # Changes to the accepted pair or custodies need a newly verified, consistently wired deployment.
        # C1 exposes address-only edits. Verify the proposed source and actual adapter code for this fixture.
        require(set(inputs) == {"adapter", "source"}, "supply the proposed fixture adapter and source")
        adapter = Web3.to_checksum_address(inputs["adapter"])
        source = Web3.to_checksum_address(inputs["source"])
        verifyRuntime(w, "MockOpeningReferenceAdapter", adapter)
        require(source == adapter, "expected fixture source to be the checked adapter")
        return vault.revise([*terms.bindings[:5], adapter, source]), sender
    require(not inputs, "unexpected action parameters")
    if action.startswith("approve"):
        require(vault.state().call() in (0, 1) and now < vault.activationCutoff().call(), "funding is closed")
        first = action == "approveA"
        amount = (
            terms.parameters.inventory0 if first else terms.parameters.inventory1 + terms.parameters.budget
        )
        token = contract(w, "CustodyToken", a["token0" if first else "token1"])
        return token.functions.approve(a["vault"], amount), sender
    if action == "publishOpening":
        require(
            c["network"] != "mainnet" and vault.state().call() in (0, 1, 2), "mock publication unavailable"
        )
        adapter = contract(w, "MockOpeningReferenceAdapter", terms.bindings.referenceAdapter)
        obs = (terms.bindings.referenceSource, a["token0"], a["token1"], 6, 6, 8, 100_000_000, now, True)
        return adapter.functions.publish(obs), sender
    if action in ("accept", "fund", "activate"):
        return getattr(vault, action)(current), sender
    if action in ("claim", "refund"):
        return getattr(contract(w, "CompensationEscrow", a["escrow"]).functions, action)(), sender
    if action == "checkpoint":
        return contract(w, "ServiceHook", a["hook"]).functions.checkpoint(), sender
    return getattr(vault, action)(), sender


# Resolve only a compiled view or pure selector, with all values evaluated at a single checked block.
def readFunction(w, m, target, function, args):
    supported = {"vault", "hook", "escrow", "quote", "token0", "token1", "adapter"}
    require(target in supported, "unknown read target")
    head = w.eth.get_block("latest")
    address = m["addresses"][target]
    if target == "adapter":
        vault = contract(w, "AgreementVault", m["addresses"]["vault"])
        address = vault.functions.currentTerms().call(block_identifier=head.number).bindings.referenceAdapter
    name = deploymentArtifacts(m).get(target, PRODUCT[target])
    if m.get("workflow") == "forge-script" and target == "adapter" and address != m["addresses"]["adapter"]:
        # Across a revision the sole guaranteed adapter getter is the C1 observation.
        require(function == "observation", "revised adapter exposes C1 observation")
    instance = contract(w, name, address)
    entries = [
        x
        for x in instance.abi
        if x.get("type") == "function" and x["name"] == function and x["stateMutability"] in ("view", "pure")
    ]
    require(len(entries) == 1, "expected a compiled read-only function")
    val = getattr(instance.functions, function)(*args).call(block_identifier=head.number)
    require(w.eth.get_block(head.number).hash == head.hash, "observed block replaced")
    return {"block": head.number, "hash": Web3.to_hex(head.hash), "value": wire(val)}


# Reuse the browser's receipt and interval reconciliation with the actual funded event as its anchor.
def exportStatement(w, c, m):
    a = m["addresses"]
    run = SimpleNamespace(
        w=w,
        v=contract(w, "AgreementVault", a["vault"]),
        hook=contract(w, "ServiceHook", a["hook"]),
        esc=contract(w, "CompensationEscrow", a["escrow"]),
        a=contract(w, "CustodyToken", a["token0"]),
        b=contract(w, "CustodyToken", a["token1"]),
    )
    head = w.eth.get_block("latest")
    require(head.number - m["anchor"]["number"] < 128, "outside the bounded statement window")
    events = run.v.events.Funded().get_logs(from_block=m["anchor"]["number"], to_block=head.number)
    require(len(events) == 1, "expected one funded agreement")
    event = events[0]
    manifest = dict(
        m,
        schema=1,
        buildId=buildId(),
        endpoint=m["endpointId"],
        anchor={"number": event.blockNumber, "hash": Web3.to_hex(event.blockHash)},
    )
    session = SimpleNamespace(
        run=run,
        manifest=manifest,
        history=[],
        closing=False,
        verify=lambda: validateDeploymentBindings(w, c, m),
    )
    return statement(session, m["runId"], head.number, Web3.to_hex(head.hash))
