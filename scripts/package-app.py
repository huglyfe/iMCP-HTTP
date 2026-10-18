#!/usr/bin/env python3
"""Archive a verified app without modifying it or publishing anything."""

import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def metadata(app):
    if app.suffix != ".app" or app.is_symlink():
        raise ValueError("Input must be a real .app directory, not a symbolic link.")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "io.github.huglyfe.imcp-http":
        raise ValueError("Unexpected bundle identifier.")
    if info.get("CFBundleExecutable") != "IMCPHTTP":
        raise ValueError("Unexpected bundle executable.")
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"\d+", build):
        raise ValueError("Expected a numeric three-part version and integer build number.")
    if not (app / "Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md").is_file():
        raise ValueError("Bundled third-party notices are missing.")
    return version, build


def package(app, output, development=False):
    if output.resolve().is_relative_to(app.resolve()):
        raise ValueError("The output directory must be outside the input app.")
    version, build = metadata(app)
    executable = app / "Contents/MacOS/IMCPHTTP"
    architectures = set(run("lipo", "-archs", str(executable)).split())
    labels = {frozenset({"arm64"}): "arm64", frozenset({"x86_64"}): "x86_64",
              frozenset({"arm64", "x86_64"}): "universal"}
    if frozenset(architectures) not in labels:
        raise ValueError("Unsupported executable architecture set.")
    architecture = labels[frozenset(architectures)]
    run("codesign", "--verify", "--deep", "--strict", str(app))
    if not development:
        signature = run("codesign", "-d", "--verbose=4", str(app))
        hardened = re.search(r"^CodeDirectory .*flags=0x[0-9a-fA-F]+\([^)]*\bruntime\b", signature, re.MULTILINE)
        if "Authority=Developer ID Application:" not in signature or not hardened or "Timestamp=" not in signature:
            raise ValueError("Release archives require Developer ID, Hardened Runtime, and a secure timestamp. Use --development for local previews.")
        run("xcrun", "stapler", "validate", str(app))
        run("spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
    output.mkdir(parents=True, exist_ok=True)
    suffix = "-development" if development else ""
    name = f"iMCP-HTTP-{version}-build-{build}-{architecture}{suffix}.zip"
    archive = output / name
    checksum = output / f"{name}.sha256"
    if archive.exists() or checksum.exists():
        raise ValueError("Output already exists. Choose another directory or increment the build number.")
    with tempfile.TemporaryDirectory(prefix=".imcp-package-", dir=output) as temporary:
        staged = Path(temporary) / "iMCP-HTTP.app"
        run("ditto", str(app), str(staged))
        run("codesign", "--verify", "--deep", "--strict", str(staged))
        if metadata(staged) != (version, build) or set(run(
                "lipo", "-archs", str(staged / "Contents/MacOS/IMCPHTTP")).split()) != architectures:
            raise ValueError("The app changed during packaging. Quit the build and try again.")
        if not development:
            run("xcrun", "stapler", "validate", str(staged))
            run("spctl", "--assess", "--type", "execute", "--verbose=2", str(staged))
        zipped = Path(temporary) / name
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staged), str(zipped))
        digest = hashlib.sha256(zipped.read_bytes()).hexdigest()
        # Exclusive creation refuses to replace a previously packaged release.
        created = []
        try:
            with archive.open("xb") as destination:
                created.append(archive)
                with zipped.open("rb") as source:
                    shutil.copyfileobj(source, destination)
            with checksum.open("x") as destination:
                created.append(checksum)
                destination.write(f"{digest}  {name}\n")
        except BaseException:
            for path in created:
                path.unlink(missing_ok=True)
            raise
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("dist/packages"))
    parser.add_argument("--development", action="store_true",
                        help="Allow an ad-hoc app; label the archive as a development preview.")
    args = parser.parse_args()
    try:
        print(package(args.app.absolute(), args.output_dir.absolute(), args.development))
    except (ValueError, OSError, KeyError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Packaging failed: {error}\n")


if __name__ == "__main__":
    main()
