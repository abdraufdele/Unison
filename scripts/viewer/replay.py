"""Run Chromium journeys against an owned loopback preview and fresh disposable fixtures."""

import json
import os
from pathlib import Path
import socket
import subprocess
import signal
import tempfile
import time
from urllib.request import Request, urlopen
from urllib.error import URLError

ROOT = Path(__file__).resolve().parents[2]


# Wait for the child process's startup endpoint with a bounded deadline.
def awaitEndpoint(url, child):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        if child.poll() is not None:
            raise RuntimeError("owned child exited during startup")
        try:
            with urlopen(url, timeout=2) as response:
                return response.read()
        except (URLError, TimeoutError):
            time.sleep(0.2)
    raise TimeoutError(url)


# Check port availability before starting either listener to avoid touching an existing demo.
def checkPorts():
    for port in (5173, 18547):
        with socket.socket() as s:
            s.bind(("127.0.0.1", port))


# Wait for a terminal command on the owned launcher and authenticate the resulting stage and run.
def awaitStage(launcher, stage, runId, reset=False):
    request = Request("http://127.0.0.1:18547/controls", headers={"Origin": "http://127.0.0.1:5173"})
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline and launcher.poll() is None:
        try:
            with urlopen(request, timeout=2) as response:
                state = json.load(response)
            if state["stage"] == stage and (state["runId"] != runId if reset else state["runId"] == runId):
                return state["runId"]
        except (URLError, TimeoutError):
            pass
        time.sleep(0.1)
    raise RuntimeError(f"owned launcher did not reach {stage}")


# Compare each reader state with its fixed vector, then challenge transport, chain, code and stale identity.
def checkReader(launcher, manifest):
    runId = manifest["runId"]

    # Execute the original Chromium read assertions against the owned preview.
    def checkPhase(phase, *args):
        subprocess.run(["node", "viewer/check-browser.mjs", phase, *args], cwd=ROOT, check=True, timeout=90)

    checkPhase("funded")
    for action, stage, phase in (
        ("activate", "activate", "active"),
        ("interrupt", "interrupt", "interrupted"),
        ("terminate", "shortClose", "terminal"),
    ):
        launcher.stdin.write(action + "\n")
        launcher.stdin.flush()
        awaitStage(launcher, stage, runId)
        checkPhase(phase)
    checkPhase("faults")
    launcher.stdin.write("reset " + runId + "\n")
    launcher.stdin.flush()
    fresh = awaitStage(launcher, "funded", runId, reset=True)
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as previous:
        json.dump(manifest, previous)
        previous.flush()
        checkPhase("old-manifest", previous.name)
    return fresh


# Exercise exports, payment-independent exit and swap interruption, stopping only children started here.
def main():
    browser = os.environ.get("CHROMIUM_PATH")
    if not browser or not os.access(browser, os.X_OK):
        raise ValueError("set CHROMIUM_PATH to the installed Playwright 1193 headless_shell")
    checkPorts()
    with tempfile.TemporaryFile() as log:
        preview = subprocess.Popen(
            ["make", "-s", "viewer-preview"],
            start_new_session=True,
            cwd=ROOT,
            stdout=log,
        )
        try:
            awaitEndpoint("http://127.0.0.1:5173", preview)
            subprocess.run(
                ["make", "-s", "statements"],
                cwd=ROOT,
                check=True,
                timeout=360,
            )
            launcher = subprocess.Popen(
                ["make", "-s", "demo"],
                cwd=ROOT,
                start_new_session=True,
                stdin=subprocess.PIPE,
                stdout=log,
                text=True,
            )
            try:
                manifest = json.loads(awaitEndpoint("http://127.0.0.1:18547/deployment.json", launcher))
                marker = ("Run " + manifest["runId"] + "\n").encode()
                deadline = time.monotonic() + 10
                while marker not in os.pread(log.fileno(), 65536, 0):
                    if launcher.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("reader identity differs from the owned launcher")
                    time.sleep(0.1)
                freshRun = checkReader(launcher, manifest)
                subprocess.run(
                    ["node", "viewer/check-journey.mjs", freshRun], cwd=ROOT, check=True, timeout=300
                )
            finally:
                if launcher.poll() is None:
                    try:
                        launcher.communicate("stop\n", timeout=20)
                    except subprocess.TimeoutExpired:
                        os.killpg(launcher.pid, signal.SIGTERM)
                        launcher.wait(timeout=10)
        finally:
            if preview.poll() is None:
                os.killpg(preview.pid, signal.SIGTERM)
            preview.wait(timeout=10)


if __name__ == "__main__":
    main()
