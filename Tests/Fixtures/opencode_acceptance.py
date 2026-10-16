"""Opt-in OpenCode OAuth acceptance with isolated XDG state and no model turns.

Only phase/error types leave this process. Temporary client credentials and URLs
stay in memory or the disposable client directory, which Swift removes on exit.
"""
import json
import os
import pathlib
import queue
import re
import signal
import subprocess
import sys
import threading
import time
import urllib.request

root = pathlib.Path(sys.argv[1])
issuer = sys.argv[2]
name = "imcp-http-fixture"
env = os.environ.copy()
for key, subdir in [("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                    ("XDG_CACHE_HOME", "cache"), ("XDG_STATE_HOME", "state")]:
    env[key] = str(root / subdir)
config = root / "opencode.json"
config.write_text(json.dumps({"mcp": {name: {"type": "remote", "url": issuer + "/mcp"}}}))
env["OPENCODE_CONFIG"] = str(config)
# Avoid opening the default browser during this protocol fixture.
env["BROWSER"] = "/usr/bin/false"
(root / "home").mkdir()
env["OPENCODE_TEST_HOME"] = str(root / "home")
proc = subprocess.Popen(["opencode", "mcp", "auth", name, "--log-level", "none"],
                        cwd=root, env=env, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, text=True, bufsize=1)
messages = queue.Queue()

def drain():
    for line in proc.stdout:
        messages.put(line)
threading.Thread(target=drain, daemon=True).start()

def terminate(signum, frame):
    raise SystemExit(1)
signal.signal(signal.SIGTERM, terminate)
stage = "login"
try:
    end = time.monotonic() + 40
    url = None
    while time.monotonic() < end:
        try:
            line = messages.get(timeout=1)
        except queue.Empty:
            if proc.poll() is not None:
                break
            continue
        line = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", line)
        match = re.search(re.escape(issuer) + r"/authorize\?[^\s\x1b]+", line)
        if match:
            url = match.group(0)
            break
    assert url, "No authorization URL"
    stage = "authorization page"
    with urllib.request.urlopen(url, timeout=5) as response:
        page = response.read().decode()
    pending = re.search(r"/approval\?id=([A-Za-z0-9_-]+)", page)
    stage = "approval callback"
    while pending and time.monotonic() < end:
        time.sleep(0.1)
        with urllib.request.urlopen(issuer + "/approval?id=" + pending.group(1), timeout=5) as response:
            page = response.read().decode()
        if "/approval?id=" not in page:
            break
    proc.wait(timeout=10)
    stage = "client completion"
    assert proc.returncode == 0
    print("Real OpenCode: dynamic registration and OAuth login passed. Tool/restart/revoke acceptance remains unverified.", flush=True)
except Exception as error:
    print("OpenCode acceptance failed at " + stage + ": " + type(error).__name__, flush=True)
    sys.exit(1)
finally:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
