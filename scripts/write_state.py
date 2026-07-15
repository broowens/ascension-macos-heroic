#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    for name in (
        "output",
        "version",
        "prefix",
        "runner",
        "runner-backup",
        "runtime-backup",
        "config",
        "config-backup",
        "vc-version",
    ):
        parser.add_argument(f"--{name}", required=True)
    args = parser.parse_args()
    data = vars(args)
    data["installed_at"] = datetime.now(timezone.utc).isoformat()
    output = Path(data.pop("output"))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
