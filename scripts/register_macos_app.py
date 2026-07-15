#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import plistlib
import shlex
from pathlib import Path


APP_NAME = "Project Ascension"
BUNDLE_IDENTIFIER = "com.broowens.ascension-macos-heroic"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-id", required=True)
    parser.add_argument(
        "--applications-dir", type=Path, default=Path.home() / "Applications"
    )
    args = parser.parse_args()

    app = args.applications_dir.expanduser() / f"{APP_NAME}.app"
    contents = app / "Contents"
    executable = contents / "MacOS" / "launch"
    executable.parent.mkdir(parents=True, exist_ok=True)

    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleDisplayName": APP_NAME,
        "CFBundleExecutable": executable.name,
        "CFBundleIdentifier": BUNDLE_IDENTIFIER,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": APP_NAME,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSApplicationCategoryType": "public.app-category.games",
        "LSMinimumSystemVersion": "12.0",
    }
    with (contents / "Info.plist").open("wb") as plist:
        plistlib.dump(info, plist, sort_keys=True)

    protocol = f"heroic://launch?appName={args.app_id}&runner=sideload"
    script = f'''#!/bin/bash
set -euo pipefail

exec /usr/bin/open {shlex.quote(protocol)}
'''
    executable.write_text(script)
    os.chmod(executable, 0o755)

    print(app)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
