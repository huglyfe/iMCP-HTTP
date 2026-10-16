#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift format lint --strict --recursive Package.swift Sources Tests
for script in scripts/*.sh; do bash -n "$script"; done
python3 scripts/check-repository.py
swift test -j 2 --force-resolved-versions --disable-xctest "$@"
# Checks must not overwrite the normal development app, which may be running.
export IMCP_BUILD_APP_PATH="${IMCP_BUILD_APP_PATH:-$PWD/.build/check/iMCP-HTTP.app}"
./scripts/build-app.sh debug
git diff --check
git diff --cached --check
echo "Repository, tests, build, bundle, and formatting checks passed. See docs/PLAN.md for native acceptance."
