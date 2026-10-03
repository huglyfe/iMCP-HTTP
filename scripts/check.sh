#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift format lint --strict --recursive Package.swift Sources Tests
bash -n scripts/build-app.sh scripts/check.sh
swift test -j 2 --disable-xctest "${@}"
./scripts/build-app.sh debug
plutil -lint dist/iMCP-HTTP.app/Contents/Info.plist
codesign --verify --strict dist/iMCP-HTTP.app
git diff --check
echo "Build, tests, bundle and formatting checks passed. See docs/PLAN.md for manual acceptance."
