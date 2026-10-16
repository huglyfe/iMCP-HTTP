#!/usr/bin/env python3
"""Copy notices for the locked dependency graph into a fresh app bundle."""
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def main():
    destination = Path(sys.argv[1])
    # Vendored notices must be revisited when these pinned source revisions change.
    for package, subpath, revision in [
        ("swift-nio-ssl", "CNIOBoringSSL", "817ab07ebb53da35afea409ab9328f578492832d"),
        ("swift-crypto", "CCryptoBoringSSL", "0226f30467f540a3f62ef48d453f93927da199b6"),
    ]:
        origin = ROOT / ".build/checkouts" / package / "Sources" / subpath / "hash.txt"
        if not origin.is_file() or revision not in origin.read_text():
            raise SystemExit(f"Review LICENSES/ and vendored BoringSSL notices for {package}")
    for name in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "Package.resolved"):
        copy(ROOT / name, destination / name)
    for source in (ROOT / "LICENSES").iterdir():
        if source.is_file():
            copy(source, destination / "LICENSES" / source.name)
    checkouts = {p.name.lower(): p for p in (ROOT / ".build/checkouts").iterdir() if p.is_dir()}
    pins = json.loads((ROOT / "Package.resolved").read_text())["pins"]
    for pin in pins:
        identity = pin["identity"]
        checkout = checkouts.get(identity)
        if checkout is None:
            raise SystemExit(f"Missing resolved checkout: {identity}")
        notices = [p for p in checkout.iterdir() if p.is_file() and
                   p.name.upper().startswith(("LICENSE", "NOTICE", "COPYING"))]
        if not any(p.name.upper().startswith(("LICENSE", "COPYING")) for p in notices):
            raise SystemExit(f"Missing dependency license: {identity}")
        # Include component notices such as SwiftNIO's bundled llhttp license.
        if (checkout / "Sources").is_dir():
            notices += [p for p in (checkout / "Sources").rglob("*") if p.is_file() and
                        p.name.upper().startswith(("LICENSE", "NOTICE", "COPYING"))]
        for notice in notices:
            copy(notice, destination / identity / notice.relative_to(checkout))
    print(f"Bundled notices for {len(pins)} resolved dependencies.")


if __name__ == "__main__":
    main()
