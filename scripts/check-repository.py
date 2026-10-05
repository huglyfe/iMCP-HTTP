#!/usr/bin/env python3
"""Check portable docs, release metadata, and accidental runtime artifacts."""
import ast
import json
from pathlib import Path
import plistlib
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def main():
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
    ).decode().split("\0")
    errors = []
    for name in sorted(set(paths) - {""}):
        path = ROOT / name
        if not path.is_file():
            continue  # Deletions are valid worktree changes.
        forbidden = any(part in {".build", ".swiftpm", ".runtime", "dist", "__pycache__"}
                        or part.endswith(".app") for part in path.relative_to(ROOT).parts)
        if forbidden or (path.name.startswith(".env") and path.name != ".env.example") or path.name in {"grants.json", "services.json", ".DS_Store"} or path.suffix.lower() in {
            ".key", ".p8", ".p12", ".pfx", ".pem", ".mobileprovision", ".db", ".db-shm", ".db-wal", ".sqlite", ".sqlite3", ".log", ".pyc"
        }:
            errors.append(f"Runtime/generated/private artifact in source tree: {name}")
        if path.suffix == ".py":
            ast.parse(path.read_text(), filename=name)
        if path.suffix == ".md":
            for target in re.findall(r"\]\(([^\s)]+)\)", path.read_text()):
                url = urlsplit(target)
                if url.scheme or not url.path:
                    continue
                linked = path.parent / unquote(url.path)
                if url.path.startswith("/") or not linked.exists():
                    errors.append(f"Nonportable or broken local link in {name}: {target}")
    info = plistlib.loads((ROOT / "App/Info.plist").read_bytes())
    gateway = (ROOT / "Sources/IMCPCore/Server/MCPGateway.swift").read_text()
    version = re.search(r'var serverVersion: String \{ "([^"]+)" \}', gateway).group(1)
    if info["CFBundleShortVersionString"] != version.split("-")[0]:
        errors.append("Bundle and MCP versions disagree")
    for document in ("README.md", "CHANGELOG.md"):
        if version not in (ROOT / document).read_text():
            errors.append(f"Current alpha version missing from {document}")
    license_text = (ROOT / "LICENSE").read_text()
    if "Apache License" not in license_text or "Version 2.0, January 2004" not in license_text:
        errors.append("Expected Apache-2.0 application license")
    json.loads((ROOT / "Package.resolved").read_text())
    if errors:
        raise SystemExit("\n".join(errors))
    print("Repository metadata, local documentation links, and source-file hygiene passed.")


if __name__ == "__main__":
    main()
