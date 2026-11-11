"""Portable checks for fork build numbers, tags, and the generated update feed."""

import copy
import hashlib
from pathlib import Path
import plistlib
import runpy
import tempfile
import unittest

release = runpy.run_path(str(Path(__file__).resolve().parents[2] / "scripts/fork-release.py"))


class ForkReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="oilfind-fork-release-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.plist = self.root / "Info.plist"
        self.info = {"CFBundleShortVersionString": "1.8.2", "CFBundleVersion": "22", "LSMinimumSystemVersion": "14.0"}
        self.plist.write_bytes(plistlib.dumps(self.info))
        self.archive = self.root / "Oil-Find-macOS.zip"
        self.archive.write_bytes(b"archive bytes")

    def test_build_numbers_are_newer_and_increase_with_runs(self):
        self.assertEqual(release["prepare"](self.plist, 1), 1_000_001)
        self.assertEqual(release["prepare"](self.plist, 2), 1_000_002)
        self.assertEqual(plistlib.loads(self.plist.read_bytes())["CFBundleShortVersionString"], "1.8.2")
        for number in (-1, 0, 1, 2, 2**63):
            with self.assertRaises(ValueError):
                release["prepare"](self.plist, number)

    def test_tag_metadata_does_not_turn_app_version_into_prerelease(self):
        for tag in ("v1.8.2", "v1.8.2+sfw.1", "v1.8.2+sfw.42"):
            release["validate_tag"]("1.8.2", tag)
        for tag in ("v1.8.3", "v1.8.2-sfw.1", "v1.8.2+sfw.01", "v1.8.2+sfw.1/escape", "1.8.2"):
            with self.assertRaises(ValueError):
                release["validate_tag"]("1.8.2", tag)
        with self.assertRaises(ValueError):
            release["prepare"](self.plist, 1, "v1.8.3")
        self.assertEqual(plistlib.loads(self.plist.read_bytes()), self.info)

    def test_manifest_contains_actual_size_hash_and_nonempty_bilingual_notes(self):
        release["prepare"](self.plist, 1)
        value = release["manifest"](self.plist, self.archive, "v1.8.2+sfw.1")
        self.assertEqual(value["build"], 1_000_001)
        self.assertEqual(value["version"], "1.8.2")
        self.assertEqual(value["url"], "https://github.com/sfw003/oil-find/releases/download/v1.8.2+sfw.1/Oil-Find-macOS.zip")
        self.assertEqual(value["size"], self.archive.stat().st_size)
        self.assertEqual(value["sha256"], hashlib.sha256(self.archive.read_bytes()).hexdigest())
        release["validate_manifest"](value)
        noted = release["manifest"](self.plist, self.archive, "v1.8.2+sfw.1", "更新" * 10_000)
        self.assertLessEqual(len(noted["notes"]["zh"][1].encode()), 16_384)

    def test_parser_constraints_fail_closed(self):
        value = release["manifest"](self.plist, self.archive, "v1.8.2+sfw.1")
        for key, bad in (("size", 0), ("size", True), ("build", -1), ("sha256", "A" * 64),
                         ("version", "1.8.2-sfw.01"), ("minimumSystemVersion", "14.beta"),
                         ("published", "today"), ("url", "https://evil.example/test.zip"),
                         ("url", value["url"] + "?redirect=evil"), ("notes", {"zh": [], "en": ["note"]})):
            broken = copy.deepcopy(value); broken[key] = bad
            with self.assertRaises(ValueError, msg=key):
                release["validate_manifest"](broken)

    def test_semver_constraints_match_the_swift_parser(self):
        for version in ("1.8.2", "1.8.2+sfw.1", "1.9.0-rc.1", "1.0.0+001"):
            self.assertTrue(release["valid_version"](version))
        for version in ("v1.8.2", "1.8", "01.8.2", "1.8.2-01", "1.8.2+", "1.8.2+a+b", "18446744073709551616.0.0"):
            self.assertFalse(release["valid_version"](version))


if __name__ == "__main__":
    unittest.main()
