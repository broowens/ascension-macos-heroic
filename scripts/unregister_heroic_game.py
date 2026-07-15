#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any


TITLE = "Project Ascension"


def belongs_to_prefix(game: Any, prefix: Path) -> bool:
    if not isinstance(game, dict) or game.get("title") != TITLE:
        return False
    install = game.get("install")
    executable = install.get("executable") if isinstance(install, dict) else None
    if not isinstance(executable, str) or not executable:
        return False
    try:
        Path(executable).expanduser().resolve().relative_to(prefix)
    except (OSError, RuntimeError, ValueError):
        return False
    return True


def write_json(path: Path, value: Any) -> None:
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--heroic-data", required=True, type=Path)
    args = parser.parse_args()

    prefix = args.prefix.expanduser().resolve()
    heroic_data = args.heroic_data.expanduser()
    library_path = heroic_data / "sideload_apps/library.json"
    if not library_path.exists():
        return 0

    library = json.loads(library_path.read_text())
    games = library.get("games") if isinstance(library, dict) else None
    if not isinstance(games, list):
        parser.error(f"Unexpected Heroic sideload library structure: {library_path}")

    removed_ids = {
        game.get("app_name")
        for game in games
        if belongs_to_prefix(game, prefix) and isinstance(game.get("app_name"), str)
    }
    library["games"] = [game for game in games if not belongs_to_prefix(game, prefix)]
    if len(library["games"]) != len(games):
        write_json(library_path, library)

    config_dir = heroic_data / "GamesConfig"
    for app_id in removed_ids:
        (config_dir / f"{app_id}.json").unlink(missing_ok=True)
        for backup in config_dir.glob(f"{app_id}.json.ascension-backup-*"):
            backup.unlink()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
