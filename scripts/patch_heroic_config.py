#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any


ENVIRONMENT = {
    "ROSETTA_X87_EXTENDED_FPR_SCRATCH": "1",
    "WINEMSYNC": "1",
    "WINEDLLOVERRIDES": "d3d9=n,b;DivxDecoder=b,n;msvcp140=n,b;vcruntime140=n,b;ucrtbase=n,b;concrt140=n,b;winemenubuilder.exe=d;mscoree=d;mshtml=d",
    "DXVK_ASYNC": "1",
    "DXVK_STATE_CACHE": "0",
    "DXVK_LOG_LEVEL": "none",
}


def game_settings(document: dict[str, Any]) -> list[dict[str, Any]]:
    return [value for value in document.values() if isinstance(value, dict)]


def candidate_configs(prefix: Path) -> list[Path]:
    root = Path.home() / "Library/Application Support/heroic/GamesConfig"
    matches: list[Path] = []
    for path in root.glob("*.json"):
        try:
            document = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        for settings in game_settings(document):
            configured = settings.get("winePrefix")
            if configured and Path(configured).expanduser().resolve() == prefix.resolve():
                matches.append(path)
                break
    return matches


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--runner", required=True, type=Path)
    parser.add_argument("--stamp", required=True)
    parser.add_argument("--config", type=Path)
    args = parser.parse_args()

    if args.config:
        config = args.config.expanduser()
    else:
        matches = candidate_configs(args.prefix)
        if len(matches) != 1:
            print(
                f"Expected one Heroic config for {args.prefix}, found {len(matches)}. "
                "Use --config.",
                file=sys.stderr,
            )
            return 1
        config = matches[0]

    document = json.loads(config.read_text())
    settings_list = game_settings(document)
    if len(settings_list) != 1:
        print(f"Unexpected Heroic config structure: {config}", file=sys.stderr)
        return 1
    settings = settings_list[0]

    backup = config.with_name(f"{config.name}.ascension-backup-{args.stamp}")
    shutil.copy2(config, backup)

    environment = {
        item.get("key"): item.get("value")
        for item in settings.get("enviromentOptions", [])
        if isinstance(item, dict) and item.get("key")
    }
    environment.update(ENVIRONMENT)
    environment["ROSETTA_X87_PATH"] = str(
        args.runner / "support/ascension-runtime/rosettax87"
    )

    settings.update(
        {
            "autoInstallDxvk": False,
            "autoInstallDxvkNvapi": False,
            "autoInstallVkd3d": False,
            "preferSystemLibs": False,
            "enableEsync": False,
            "enableMsync": True,
            "enableFsync": False,
            "enableWineWayland": False,
            "enableHDR": False,
            "enableWoW64": False,
            "launcherArgs": "--no-sandbox --disable-gpu-sandbox --disable-gpu --use-angle=swiftshader",
            "enviromentOptions": [
                {"key": key, "value": value} for key, value in environment.items()
            ],
            "winePrefix": str(args.prefix),
            "wineVersion": {
                "wineserver": str(args.runner / "bin/wineserver"),
                "lib": str(args.runner / "lib"),
                "lib32": str(args.runner / "lib"),
                "bin": str(args.runner / "bin/wine-heroic"),
                "name": "WineCX 26 RosettaX87 MinGW (Ascension)",
                "type": "wine",
            },
        }
    )

    fd, temporary_name = tempfile.mkstemp(prefix=config.name, dir=config.parent)
    try:
        with os.fdopen(fd, "w") as temporary:
            json.dump(document, temporary, indent=2)
            temporary.write("\n")
        os.replace(temporary_name, config)
    except BaseException:
        Path(temporary_name).unlink(missing_ok=True)
        raise

    print(config)
    print(backup)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
