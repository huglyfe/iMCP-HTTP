#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift format lint --strict --recursive Package.swift Sources
bash -n scripts/build-app.sh scripts/check.sh
./scripts/build-app.sh debug
plutil -lint dist/iMCP-HTTP.app/Contents/Info.plist
codesign --verify --strict dist/iMCP-HTTP.app
git diff --check
echo "Skeleton checks passed. OAuth, MCP, and Apple-service acceptance are not implemented."
