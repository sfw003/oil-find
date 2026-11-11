#!/usr/bin/env python3
"""Prepare fork build metadata and generate a standalone GitHub release feed."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re

BUILD_BASE = 1_000_000
INT_MAX = 2**63 - 1
RELEASE_PREFIX = "https://github.com/sfw003/oil-find/releases/download/"
IDENTIFIERS = r"[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*"
SEMVER = re.compile(rf"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-({IDENTIFIERS}))?(?:\+({IDENTIFIERS}))?")


def valid_version(version):
    match = SEMVER.fullmatch(version)
    if not match or any(int(part) > 2**64 - 1 for part in match.groups()[:3]):
        return False
    return not match[4] or all(not part.isdigit() or len(part) == 1 or part[0] != "0" for part in match[4].split("."))


def validate_tag(version, tag):
    # +sfw.N is tag metadata, not a lower-precedence SemVer prerelease.
    if not valid_version(version) or not (tag == "v" + version or (
            "+" not in version and re.fullmatch(re.escape("v" + version) + r"\+sfw\.[1-9][0-9]*", tag))):
        raise ValueError("Tag must be v<Info.plist version> or v<version>+sfw.N")


def prepare(plist, run_number, tag=None):
    with plist.open("rb") as source:
        info = plistlib.load(source)
    if not valid_version(info["CFBundleShortVersionString"]):
        raise ValueError("Info.plist version must be SemVer")
    if tag:
        validate_tag(info["CFBundleShortVersionString"], tag)
    build = BUILD_BASE + run_number
    if run_number <= 0 or build > INT_MAX or build <= int(info["CFBundleVersion"]):
        raise ValueError("Fork build must be newer than the source build; increase BUILD_BASE if needed")
    info["CFBundleVersion"] = str(build)
    with plist.open("wb") as target:
        plistlib.dump(info, target)
    return build


def require(condition):
    if not condition:
        raise ValueError("Invalid fork update manifest")


def validate_manifest(value):
    """Mirror UpdateManifest.parse field constraints, plus the fork URL policy."""
    require(valid_version(value["version"]))
    require(type(value["build"]) is int and 0 <= value["build"] <= INT_MAX)
    require(type(value["size"]) is int and 0 < value["size"] <= INT_MAX)
    require(re.fullmatch(r"[0-9a-f]{64}", value["sha256"]))
    require(re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value["minimumSystemVersion"]))
    require(all(int(part) <= INT_MAX for part in value["minimumSystemVersion"].split(".")))
    require(re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value["published"]))
    for language in ("zh", "en"):
        require(type(value["notes"][language]) is list and value["notes"][language])
        require(all(type(note) is str and 0 < len(note.encode()) <= 16_384 for note in value["notes"][language]))
    require(value["url"].startswith(RELEASE_PREFIX))
    parts = value["url"][len(RELEASE_PREFIX):].split("/")
    require(len(parts) == 2 and all(part and part not in (".", "..") for part in parts))
    require(not any(character in value["url"] for character in "?#%") and value["url"].endswith(".zip"))
    require(len(json.dumps(value, ensure_ascii=False).encode()) <= 1_048_576)


def manifest(plist, archive, tag, notes=""):
    with plist.open("rb") as source:
        info = plistlib.load(source)
    version = info["CFBundleShortVersionString"]
    validate_tag(version, tag)
    digest = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1_048_576), b""):
            digest.update(chunk)
    note = notes.strip().encode()[:16_384].decode("utf-8", errors="ignore").strip()
    value = {
        "version": version, "build": int(info["CFBundleVersion"]),
        "url": RELEASE_PREFIX + tag + "/" + archive.name,
        "size": archive.stat().st_size, "sha256": digest.hexdigest(),
        "minimumSystemVersion": info["LSMinimumSystemVersion"],
        "published": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "notes": {"zh": ["此版本包含 fork 的维护更新。"], "en": ["This release includes fork maintenance updates."]},
    }
    if note:
        value["notes"]["zh"].append(note)
        value["notes"]["en"].append(note)
    validate_manifest(value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("prepare")
    build.add_argument("--plist", type=Path, default=Path("Resources/Info.plist"))
    build.add_argument("--run-number", type=int, required=True)
    build.add_argument("--tag")
    feed = commands.add_parser("manifest")
    feed.add_argument("--plist", type=Path, required=True)
    feed.add_argument("--archive", type=Path, required=True)
    feed.add_argument("--tag", required=True)
    feed.add_argument("--notes-file", type=Path)
    feed.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        print("Fork build:", prepare(args.plist, args.run_number, args.tag))
    else:
        notes = args.notes_file.read_text() if args.notes_file else ""
        value = manifest(args.plist, args.archive, args.tag, notes)
        args.output.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
        print("Validated manifest:", args.output)


if __name__ == "__main__":
    main()
