#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-debug}"
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

swift build -j 2 --configuration "$configuration" --product IMCPHTTP
bin_path="$(swift build -j 2 --configuration "$configuration" --show-bin-path)"
app_path="$PWD/dist/iMCP-HTTP.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/IMCPHTTP" "$app_path/Contents/MacOS/IMCPHTTP"
cp App/Info.plist "$app_path/Contents/Info.plist"
# Include licenses for the resolved dependency graph in every development bundle.
notices="$app_path/Contents/Resources/Licenses"
mkdir -p "$notices"
cp LICENSE THIRD_PARTY_NOTICES.md "$notices/"
cp LICENSES/* "$notices/"
shopt -s nullglob
for dependency in .build/checkouts/*; do
    for notice in "$dependency"/LICENSE* "$dependency"/NOTICE* "$dependency"/COPYING*; do
        if [[ -f "$notice" ]]; then
            destination="$notices/$(basename "$dependency")"
            mkdir -p "$destination"
            # SwiftPM license files may be read-only; replace a previous copied notice.
            cp -f "$notice" "$destination/"
        fi
    done
done
codesign --force --sign - "$app_path"
echo "$app_path"
