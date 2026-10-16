#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-debug}"
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

app_path="${IMCP_BUILD_APP_PATH:-$PWD/dist/iMCP-HTTP.app}"
if [[ "$app_path" != /*.app ]]; then
    echo "IMCP_BUILD_APP_PATH must be an absolute .app path." >&2
    exit 2
fi
mkdir -p "$(dirname "$app_path")"
app_path="$(cd "$(dirname "$app_path")" && pwd -P)/$(basename "$app_path")"
# Changing a running ad-hoc signed bundle can invalidate its Apple permissions.
ensure_target_stopped() {
python3 - "$app_path" <<'PYTHON'
from pathlib import Path
import subprocess
import sys

target = (Path(sys.argv[1]) / "Contents/MacOS/IMCPHTTP").resolve()
processes = subprocess.check_output(["ps", "-axww", "-o", "comm="], text=True)
for command in processes.splitlines():
    command = command.strip()
    if command.endswith("/Contents/MacOS/IMCPHTTP") and Path(command).resolve() == target:
        raise SystemExit("Quit the target app or choose a different IMCP_BUILD_APP_PATH before rebuilding.")
PYTHON
}
ensure_target_stopped

swift build -j 2 --force-resolved-versions --configuration "$configuration" --product IMCPHTTP
bin_path="$(swift build --force-resolved-versions --configuration "$configuration" --show-bin-path)"
work_path="$(mktemp -d "$(dirname "$app_path")/.imcp-build.XXXXXX")"
trap 'rm -rf "$work_path"' EXIT
bundle="$work_path/iMCP-HTTP.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_path/IMCPHTTP" "$bundle/Contents/MacOS/IMCPHTTP"
shopt -s nullglob
for resource in "$bin_path"/*.bundle; do
    ditto "$resource" "$bundle/Contents/Resources/$(basename "$resource")"
done
cp App/Info.plist "$bundle/Contents/Info.plist"
# Keep the approved artwork as the source; generate all standard macOS sizes.
iconset="$work_path/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips --resampleHeightWidth "$size" "$size" App/AppIcon.png \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips --resampleHeightWidth "$double_size" "$double_size" App/AppIcon.png \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$bundle/Contents/Resources/AppIcon.icns" "$iconset"
python3 scripts/bundle-notices.py "$bundle/Contents/Resources/Licenses"
plutil -lint "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
ensure_target_stopped
# Replace only after a complete, verified build; stale resources never carry forward.
if [[ -e "$app_path" ]]; then mv "$app_path" "$work_path/previous.app"; fi
if ! mv "$bundle" "$app_path"; then
    if [[ -e "$work_path/previous.app" ]]; then mv "$work_path/previous.app" "$app_path"; fi
    exit 1
fi
echo "$app_path"
