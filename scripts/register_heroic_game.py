#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import secrets
from pathlib import Path
from typing import Any


TITLE = "Project Ascension"
ART_URL = "https://cdn2.steamgriddb.com/grid/37ab40d14e0dd1eab61638717931eed3.png"


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text())


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--heroic-data", required=True, type=Path)
    args = parser.parse_args()

    prefix = args.prefix.expanduser().resolve()
    launcher_dir = prefix / "drive_c/Program Files/Ascension Launcher"
    batch = launcher_dir / "Launch Ascension.bat"
    launcher = launcher_dir / "Ascension Launcher.exe"
    executable = batch if batch.exists() else launcher
    if not executable.exists():
        parser.error(f"Ascension Launcher is missing from {launcher_dir}")

    library_path = args.heroic_data.expanduser() / "sideload_apps/library.json"
    library = read_json(library_path, {"games": []})
    if not isinstance(library, dict) or not isinstance(library.get("games"), list):
        parser.error(f"Unexpected Heroic sideload library structure: {library_path}")

    game: dict[str, Any] | None = None
    for candidate in library["games"]:
        if not isinstance(candidate, dict):
            continue
        installed = candidate.get("install")
        configured_executable = installed.get("executable") if isinstance(installed, dict) else None
        if candidate.get("title") == TITLE and configured_executable:
            try:
                Path(configured_executable).resolve().relative_to(prefix)
                game = candidate
                break
            except (OSError, RuntimeError, ValueError):
                continue

    app_id = game.get("app_name") if game else None
    if not isinstance(app_id, str) or not app_id:
        app_id = secrets.token_urlsafe(18).replace("-", "").replace("_", "")[:22]
        game = {}
        library["games"].append(game)

    game.update(
        {
            "runner": "sideload",
            "app_name": app_id,
            "title": TITLE,
            "install": {
                "executable": str(executable),
                "platform": "Windows",
                "is_dlc": False,
            },
            "folder_name": str(launcher_dir),
            "art_cover": ART_URL,
            "is_installed": True,
            "art_square": ART_URL,
            "canRunOffline": True,
            "browserUrl": "",
            "customUserAgent": "",
            "launchFullScreen": False,
        }
    )
    write_json(library_path, library)

    config_path = args.heroic_data.expanduser() / "GamesConfig" / f"{app_id}.json"
    config = read_json(config_path, {app_id: {}, "version": "v0", "explicit": True})
    if not isinstance(config, dict):
        parser.error(f"Unexpected Heroic game config structure: {config_path}")
    settings = config.setdefault(app_id, {})
    if not isinstance(settings, dict):
        parser.error(f"Unexpected Heroic game settings structure: {config_path}")
    settings["winePrefix"] = str(prefix)
    config.setdefault("version", "v0")
    config.setdefault("explicit", True)
    write_json(config_path, config)

    print(config_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
