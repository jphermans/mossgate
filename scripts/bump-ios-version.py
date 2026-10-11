#!/usr/bin/env python3
"""Bump the Mossgate iOS version and regenerate the Xcode project.

The version lives in ios/project.yml (xcodegen turns it into the pbxproj and
Info.plist), so this is the single place that needs to change.

Usage:
    ./scripts/bump-ios-version.py             # build +1            (every batch)
    ./scripts/bump-ios-version.py --patch     # 0.1.0 -> 0.1.1, build +1
    ./scripts/bump-ios-version.py --minor     # 0.1.0 -> 0.2.0, build +1
    ./scripts/bump-ios-version.py --major     # 0.1.0 -> 1.0.0, build +1
    ./scripts/bump-ios-version.py --set 0.2.3 # explicit marketing version
    ./scripts/bump-ios-version.py --no-xcodegen

CURRENT_PROJECT_VERSION (CFBundleVersion) must strictly increase for every
build uploaded to App Store Connect, so it is always bumped.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

REPO = Path(__file__).resolve().parent.parent
PROJECT_YML = REPO / "ios" / "project.yml"
XCODEGEN = shutil.which("xcodegen") or "/opt/homebrew/bin/xcodegen"

MARKETING_RE = re.compile(r'^(?P<indent>\s*)MARKETING_VERSION:\s*"(?P<v>[^"]+)"', re.M)
BUILD_RE = re.compile(r'^(?P<indent>\s*)CURRENT_PROJECT_VERSION:\s*"(?P<v>[^"]+)"', re.M)


def die(msg: str) -> NoReturn:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def bump_marketing(current: str, kind: str) -> str:
    parts = current.split(".")
    while len(parts) < 3:
        parts.append("0")
    try:
        major, minor, patch = (int(p) for p in parts[:3])
    except ValueError:
        die(f'MARKETING_VERSION "{current}" is not numeric x.y.z')

    if kind == "patch":
        patch += 1
    elif kind == "minor":
        minor, patch = minor + 1, 0
    elif kind == "major":
        major, minor, patch = major + 1, 0, 0
    return f"{major}.{minor}.{patch}"


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--patch", action="store_true", help="0.1.0 -> 0.1.1")
    g.add_argument("--minor", action="store_true", help="0.1.0 -> 0.2.0")
    g.add_argument("--major", action="store_true", help="0.1.0 -> 1.0.0")
    g.add_argument("--set", metavar="X.Y.Z", help="set an explicit version")
    ap.add_argument("--no-xcodegen", action="store_true", help="skip xcodegen")
    args = ap.parse_args()

    if not PROJECT_YML.exists():
        die(f"not found: {PROJECT_YML}")
    src = PROJECT_YML.read_text()

    m = MARKETING_RE.search(src)
    b = BUILD_RE.search(src)
    if not m or not b:
        die("could not find MARKETING_VERSION / CURRENT_PROJECT_VERSION in project.yml")

    old_marketing = m.group("v")
    old_build = int(b.group("v"))

    if args.set:
        if not re.fullmatch(r"\d+\.\d+(\.\d+)?", args.set):
            die("--set expects X.Y or X.Y.Z")
        new_marketing = args.set
    elif args.patch or args.minor or args.major:
        kind = "patch" if args.patch else ("minor" if args.minor else "major")
        new_marketing = bump_marketing(old_marketing, kind)
    else:
        new_marketing = old_marketing

    new_build = old_build + 1

    if new_marketing == old_marketing and new_build == old_build:
        print("nothing to do")
        return 0

    src = MARKETING_RE.sub(lambda mm: f'{mm.group("indent")}MARKETING_VERSION: "{new_marketing}"', src, count=1)
    src = BUILD_RE.sub(lambda mm: f'{mm.group("indent")}CURRENT_PROJECT_VERSION: "{new_build}"', src, count=1)
    PROJECT_YML.write_text(src)

    print(f"version: {old_marketing} ({old_build})  ->  {new_marketing} ({new_build})")

    if args.no_xcodegen:
        print("skipped xcodegen (--no-xcodegen); run it before building")
        return 0

    if not Path(XCODEGEN).exists():
        print(f"warning: xcodegen not found at {XCODEGEN}; regenerate manually", file=sys.stderr)
        return 0

    res = subprocess.run([XCODEGEN, "generate"], cwd=REPO / "ios",
                         capture_output=True, text=True)
    if res.returncode != 0:
        die(f"xcodegen failed:\n{res.stdout}\n{res.stderr}")
    print("xcodegen: project regenerated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
