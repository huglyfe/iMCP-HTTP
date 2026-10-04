"""Opt-in real Codex protocol acceptance. No model turns or production config edits.

The Swift fixture owns native approval, restart, and revocation. Only control
markers are written here; authorization URLs and credentials stay in memory.
"""
import json
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
name = "imcp-http-test-" + root.name
config = 'mcp_servers={"' + name + '"={url="' + issuer + '/mcp",oauth={client_id="codex",callback_url="http://127.0.0.1/callback"}}}'
flags = ["-c", config, "-c", 'mcp_oauth_credentials_store="keyring"']
proc = subprocess.Popen(["codex", "app-server", "--stdio", *flags], stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
messages = queue.Queue()
backlog = []

def drain():
    for line in proc.stdout:
        try:
            messages.put(json.loads(line))
        except json.JSONDecodeError:
            pass
threading.Thread(target=drain, daemon=True).start()

def has_connection(value):
    if isinstance(value, dict):
        return (value.get("connected") is True and value.get("appleDataAccessed") is False) or any(has_connection(v) for v in value.values())
    if isinstance(value, list):
        return any(has_connection(v) for v in value)
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return has_connection(parsed) if not isinstance(parsed, str) else False
        except ValueError:
            return False
    return False


def send(method, params, id=None):
    message = {"jsonrpc": "2.0", "method": method, "params": params}
    if id is not None:
        message["id"] = id
    proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()

def receive(predicate, timeout=30):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        for i, message in enumerate(backlog):
            if predicate(message):
                return backlog.pop(i)
        message = messages.get(timeout=max(0.1, end-time.monotonic()))
        backlog.append(message)
    raise TimeoutError("Codex did not respond")

def response(id):
    message = receive(lambda m: m.get("id") == id)
    if "error" in message:
        raise RuntimeError("Codex RPC failed")
    return message["result"]

def control(action):
    (root / action).touch()
    end = time.monotonic() + 20
    while not (root / (action + "-done")).exists():
        if time.monotonic() > end:
            raise TimeoutError("Fixture did not respond")
        time.sleep(0.05)

def terminate(signum, frame):
    # Swift may terminate a failing/timed-out fixture. Still run the finally block
    # so the child app-server exits and its test-only keyring credential is removed.
    raise SystemExit(1)

signal.signal(signal.SIGTERM, terminate)
stage = "initialize"
try:
    send("initialize", {"clientInfo": {"name": "imcp-http-test", "version": "1"},
                        "capabilities": {"experimentalApi": True}}, 1)
    response(1)
    send("initialized", {})
    stage = "login"
    send("mcpServer/oauth/login", {"name": name, "timeoutSecs": 40}, 2)
    auth = response(2)
    with urllib.request.urlopen(auth["authorizationUrl"], timeout=5) as r:
        page = r.read().decode()
    pending = re.search(r"/approval\?id=([A-Za-z0-9_-]+)", page)
    assert pending, "No native approval request"
    end = time.monotonic() + 30
    while time.monotonic() < end:
        time.sleep(0.1)
        with urllib.request.urlopen(issuer + "/approval?id=" + pending.group(1), timeout=5) as r:
            page = r.read().decode()
        if "/approval?id=" not in page:
            break
    complete = receive(lambda m: m.get("method") == "mcpServer/oauthLogin/completed")
    assert complete["params"]["success"], "OAuth did not complete"
    stage = "thread"
    send("thread/start", {"ephemeral": True, "cwd": str(root)}, 3)
    thread = response(3)["thread"]["id"]
    stage = "discovery"
    send("mcpServerStatus/list", {"serverName": name, "threadId": thread}, 4)
    servers = response(4)["data"]
    assert any("connection_check" in server.get("tools", {}) for server in servers), "Tool not discovered"
    arguments = {"threadId": thread, "server": name, "tool": "connection_check", "arguments": {}}
    stage = "tool"
    send("mcpServer/tool/call", arguments, 5)
    result = response(5)
    assert has_connection(result), "Tool did not run"
    stage = "typed Reminders fixture"
    assert any("reminders_fetch" in server.get("tools", {}) for server in servers), "Reminders schema not discovered"
    send("mcpServer/tool/call", {"threadId": thread, "server": name, "tool": "reminders_fetch",
        "arguments": {"query": {"listIDs": ["fixture-list"], "due": "today", "sort": "due"}}}, 8)
    queried = response(8)
    assert "reminders" in json.dumps(queried) and "timeZone" in json.dumps(queried), "Typed query failed"
    send("mcpServer/tool/call", {"threadId": thread, "server": name, "tool": "reminders_move",
        "arguments": {"id": "fixture-id", "listID": "fixture-destination"}}, 9)
    moved = response(9)
    assert "moved-id" in json.dumps(moved) and "fixture-destination" in json.dumps(moved), "Fixture move failed"
    for request_id, tool, tool_args, expected in [
        (10, "calendar_edit", {"id": "fixture-event", "start": "2026-10-03T12:00:00Z", "span": "thisEvent", "changes": {"title": "Fixture edit"}}, "fixture-event"),
        (11, "contacts_edit", {"id": "fixture-card", "changes": {"familyName": "Fixture edit"}}, "fixture-card"),
        (13, "photos_get", {"id": "fixture-photo"}, "fixture-photo"),
        (12, "maps_directions", {"from": {"latitude": 0, "longitude": 0}, "to": {"latitude": 1, "longitude": 1}}, "distanceMeters"),
    ]:
        stage = tool + " fixture"
        assert any(tool in server.get("tools", {}) for server in servers), "Tool schema not discovered"
        send("mcpServer/tool/call", {"threadId": thread, "server": name, "tool": tool, "arguments": tool_args}, request_id)
        called = response(request_id)
        assert expected in json.dumps(called) and not called.get("isError"), "Typed tool failed"
    stage = "restart"
    control("restart")
    send("mcpServer/tool/call", arguments, 6)
    assert has_connection(response(6)), "Restart lost approval"
    stage = "revoke"
    control("revoke")
    send("mcpServer/tool/call", arguments, 7)
    denied = receive(lambda m: m.get("id") == 7)
    assert not has_connection(denied), "Revocation did not deny tool"
    assert "error" in denied or denied.get("result", {}).get("isError") is True, "No failure reported"
    print("Real Codex: OAuth, discovery, Reminders/Calendar/Contacts/Maps/Photos fixtures, restart, revocation passed.", flush=True)
except Exception as error:
    # Error messages can include URLs or tokens. Report only the stage and type.
    print("Codex acceptance failed at " + stage + ": " + type(error).__name__, flush=True)
    sys.exit(1)
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    cleanup = subprocess.run(["codex", *flags, "mcp", "logout", name], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=10, check=False)

    if cleanup.returncode != 0:
        print("Could not confirm test credential cleanup.", flush=True)
        sys.exit(1)
