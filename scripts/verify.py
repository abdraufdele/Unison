"""Check exact tool and dependency pins or inspect the freshly compiled C1 artifact surface."""

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

from web3 import Web3

ROOT = Path(__file__).resolve().parents[1]
if not __debug__:
    raise RuntimeError("dependency checks require Python assertions enabled")


# Capture successful version and revision probes; preserve nonzero subprocess status.
def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


# Verify the offline build environment and clean pinned core/Solmate checkouts.
def checkPins():
    for tool in ("forge", "cast", "anvil"):
        assert "985eeea031d79922cd654d4e94e6c3701e1c7d73" in output(tool, "--version"), tool
    compiler = Path.home() / ".svm/0.8.26/solc-0.8.26"
    assert "0.8.26+commit.8a97fa7a" in output(str(compiler), "--version")
    expectedDigest = "d5f23436f443edb85d8e76906d12f0a86ce0490e7663a9e608efeb7a93f149ef"
    with compiler.open("rb") as binary:
        assert hashlib.file_digest(binary, "sha256").hexdigest() == expectedDigest
    core = "experiments/m1/vendor/v4-core"
    for path, pin in (
        (core, "e50237c43811bd9b526eff40f26772152a42daba"),
        (core + "/lib/solmate", "4b47a19038b798b4a33d9749d25e570443520647"),
    ):
        assert output("git", "-C", path, "rev-parse", "HEAD") == pin
        assert not output("git", "-C", path, "status", "--porcelain", "--untracked-files=no"), path
    from importlib.metadata import version

    for line in (ROOT / "requirements-dev.txt").read_text().splitlines():
        if line and not line.startswith("#"):
            package, pin = line.split("==")
            assert version(package) == pin, package

    assert (
        version("web3") == "7.13.0"
        and output("node", "-v") == "v22.19.0"
        and output("npm", "-v") == "11.21.3"
    )
    subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=ROOT / "experiments/m1", check=True)
    print("Toolchain, dependency revisions and historical import match.")


# Compare every documented signature and selector with the artifact and enforce the product size limits.
def checkArtifacts():
    current = {}
    for source in sorted((ROOT / "src").glob("*.sol")):
        sourceKey = source.relative_to(ROOT).as_posix()
        sourceBytes = source.read_bytes()
        declarations = re.findall(r"^(?:abstract )?(?:contract|interface|library) (\w+)", sourceBytes.decode(), re.M)
        for name in declarations:
            data = json.loads((ROOT / "out" / source.name / f"{name}.json").read_text())
            assert data["metadata"]["settings"]["compilationTarget"] == {sourceKey: name}, name
            assert data["metadata"]["sources"][sourceKey]["keccak256"] == Web3.to_hex(Web3.keccak(sourceBytes)), name
            if data["methodIdentifiers"]:
                current[name] = data
    sections = (ROOT / "docs/SELECTORS.md").read_text().split("\n## ")[1:]
    assert {section.splitlines()[0] for section in sections} == current.keys(), "selector inventory incomplete"
    for section in sections:
        name = section.splitlines()[0]
        artifact = current[name]
        documented = {sig: selector for selector, sig in re.findall(r"\| `0x(\w+)` \| `([^`]+)`", section)}
        assert documented == artifact["methodIdentifiers"], name
        init = bytes.fromhex(artifact["bytecode"]["object"][2:])
        runtime = bytes.fromhex(artifact["deployedBytecode"]["object"][2:])
        assert len(init) <= 49152 and len(runtime) <= 24576, name
        print(
            f"{name}: {len(documented)} selectors, {len(runtime)} runtime bytes, {len(init)} creation bytes, "
            f"creation SHA-256 {hashlib.sha256(init).hexdigest()}"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("check", choices=["pins", "artifacts"])
    if parser.parse_args().check == "pins":
        checkPins()
    else:
        checkArtifacts()
