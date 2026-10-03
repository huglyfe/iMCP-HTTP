#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-debug}"
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

swift build --configuration "$configuration" --product IMCPHTTP
bin_path="$(swift build --configuration "$configuration" --show-bin-path)"
app_path="$PWD/dist/iMCP-HTTP.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/IMCPHTTP" "$app_path/Contents/MacOS/IMCPHTTP"
cp App/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
echo "$app_path"
