"""Packaging failure boundaries using synthetic apps, with no signing credentials."""

import hashlib
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("package_app", Path(__file__).with_name("package-app.py"))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Fixture.app"
        contents = self.app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "MacOS/IMCPHTTP").write_text("synthetic executable")
        (contents / "Resources/Licenses").mkdir(parents=True)
        (contents / "Resources/Licenses/THIRD_PARTY_NOTICES.md").write_text("Synthetic notices")
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "io.github.huglyfe.imcp-http",
            "CFBundleExecutable": "IMCPHTTP",
            "CFBundleShortVersionString": "0.6.0", "CFBundleVersion": "1",
        }))
        self.output = self.root / "packages"

    def commands(self, *args):
        if args[0] == "lipo":
            return "arm64"
        if args[:2] == ("codesign", "-d"):
            return "Signature=adhoc"
        if args[0] == "ditto":
            if args[1] == "-c":
                app, archive = Path(args[-2]), Path(args[-1])
                with zipfile.ZipFile(archive, "w") as zipped:
                    for path in app.rglob("*"):
                        if path.is_file():
                            zipped.write(path, path.relative_to(app.parent))
            else:
                shutil.copytree(args[1], args[2])
        return ""

    def test_development_archive_has_verified_name_content_and_checksum(self):
        with patch.object(packager, "run", side_effect=self.commands):
            archive = packager.package(self.app, self.output, development=True)
            self.assertEqual(archive.name, "iMCP-HTTP-0.6.0-build-1-arm64-development.zip")
            with zipfile.ZipFile(archive) as zipped:
                self.assertEqual(zipped.read("iMCP-HTTP.app/Contents/MacOS/IMCPHTTP"), b"synthetic executable")
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            self.assertEqual(archive.with_suffix(".zip.sha256").read_text(), f"{digest}  {archive.name}\n")
            before = archive.read_bytes()
            with self.assertRaisesRegex(ValueError, "already exists"):
                packager.package(self.app, self.output, development=True)
            self.assertEqual(archive.read_bytes(), before)

    def test_public_archive_rejects_ad_hoc_signature(self):
        with patch.object(packager, "run", side_effect=self.commands):
            with self.assertRaisesRegex(ValueError, "Developer ID"):
                packager.package(self.app, self.output)
        self.assertFalse(self.output.exists())

    def test_notarization_failure_does_not_produce_a_release(self):
        def commands(*args):
            if args[:2] == ("codesign", "-d"):
                return "Authority=Developer ID Application: Fixture\nCodeDirectory v=20500 flags=0x10000(runtime)\nTimestamp=fixture"
            if args[0] == "xcrun":
                raise subprocess.CalledProcessError(1, args, "No ticket")
            return self.commands(*args)
        with patch.object(packager, "run", side_effect=commands):
            with self.assertRaises(subprocess.CalledProcessError):
                packager.package(self.app, self.output)
        self.assertFalse(self.output.exists())

    def test_unknown_architecture_and_nested_output_are_rejected(self):
        with patch.object(packager, "run", return_value="arm64 arm64e"):
            with self.assertRaisesRegex(ValueError, "architecture"):
                packager.package(self.app, self.output, development=True)
        with self.assertRaisesRegex(ValueError, "outside"):
            packager.package(self.app, self.app / "output", development=True)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
