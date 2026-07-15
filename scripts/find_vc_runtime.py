#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


def version_for(path: Path) -> tuple[int, ...] | None:
    match = re.search(r"v(\d+(?:\.\d+)+)[\\/]", str(path))
    if not match:
        return None
    return tuple(int(part) for part in match.group(1).split("."))


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: find_vc_runtime.py PACKAGE_CACHE", file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    by_arch: dict[str, dict[tuple[int, ...], Path]] = {"x86": {}, "amd64": {}}
    for arch in by_arch:
        pattern = f"**/packages/vcRuntimeMinimum_{arch}/cab1.cab"
        for path in root.glob(pattern):
            version = version_for(path)
            if version is not None:
                by_arch[arch][version] = path

    shared = set(by_arch["x86"]) & set(by_arch["amd64"])
    if not shared:
        print("No matching x86/x64 VC++ runtime pair found.", file=sys.stderr)
        return 1

    version = max(shared)
    print(by_arch["x86"][version])
    print(by_arch["amd64"][version])
    print(".".join(str(part) for part in version))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
