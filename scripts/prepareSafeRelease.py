"""Restore only the four original Safe v1.4.1 test artifacts, without running upstream build/install scripts."""
import argparse
import base64
import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / ".local/safe-release"
URL = "https://registry.npmjs.org/@safe-global/safe-contracts/-/safe-contracts-1.4.1.tgz"
INTEGRITY = "fP1jewywSwsIniM04NsqPyVRFKPMAuirC3ftA/TA4X3Zc5EnwQp/UCJUU2PL/37/z/jMo8UUaJ+pnFNWmMU7dQ=="
ARTIFACTS = {
    "SafeL2": ("SafeL2.sol", "a57d54c0d757ca7fb86693480797de69c880878690b67061f6f9624e11def8bd"),
    "SafeProxy": ("proxies/SafeProxy.sol", "b05eaeaf7278097e52a9e9b38410de2a812c23fa3622373473e73eaa19646ecd"),
    "SafeProxyFactory": ("proxies/SafeProxyFactory.sol", "f77ccb60e95345e6583216e82feb5430098679d62aa4aeda7388df3831476997"),
    "CreateCall": ("libraries/CreateCall.sol", "37bdfe93c189361b9b7e33ccb3528c12d956093c183a5d3cdec3a30bceac147f"),
}


def releaseMatches():
    """Check the installed Hardhat artifacts offline, including constructor bytes, ABI and runtime."""
    for name, (_, digest) in ARTIFACTS.items():
        path = DESTINATION / (name + ".json")
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            return False
    return True


def restoreRelease(archive):
    """Verify the package integrity before extracting named artifacts into the ignored test fixture cache."""
    if releaseMatches():
        return
    if archive:
        data = archive.read_bytes()
    else:
        with urllib.request.urlopen(URL, timeout=120) as response:
            data = response.read()
    if base64.b64encode(hashlib.sha512(data).digest()).decode() != INTEGRITY:
        raise ValueError("Safe release archive integrity mismatch")
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as package:
        for name, (source, digest) in ARTIFACTS.items():
            path = f"package/build/artifacts/contracts/{source}/{name}.json"
            artifact = package.extractfile(path).read()
            if hashlib.sha256(artifact).hexdigest() != digest:
                raise ValueError(f"Wrong release artifact: {name}")
            with tempfile.NamedTemporaryFile(dir=DESTINATION, delete=False) as temp:
                temp.write(artifact)
            Path(temp.name).replace(DESTINATION / (name + ".json"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="use a previously downloaded release archive")
    restoreRelease(parser.parse_args().archive)
    print("Verified original Safe v1.4.1 fixture artifacts.")
