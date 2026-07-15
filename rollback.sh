#!/bin/bash
set -euo pipefail

HEROIC_ROOT="${HEROIC_ROOT:-$HOME/Games/Heroic}"
PREFIX=""

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) [[ $# -ge 2 ]] || die "Missing value for $1"; PREFIX=$2; shift 2 ;;
        --help|-h) printf 'Usage: ./rollback.sh [--prefix PATH]\n'; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

if pgrep -f '/Heroic.app/Contents/MacOS/Heroic|Ascension Launcher\.exe|ascension-live.*Ascension\.exe|MMgr64\.exe' >/dev/null 2>&1; then
    die "Close Heroic, Ascension Launcher, and Ascension before rolling back."
fi

if [[ -z "$PREFIX" ]]; then
    PREFIX=$(find "$HEROIC_ROOT/Prefixes" -path '*/.ascension-macos-fix/install.json' -print 2>/dev/null | sed 's#/.ascension-macos-fix/install.json$##' | head -n 1)
fi
[[ -n "$PREFIX" ]] || die "No installation state found. Use --prefix."
STATE="$PREFIX/.ascension-macos-fix/install.json"
[[ -f "$STATE" ]] || die "Installation state not found: $STATE"
PYTHON=$(command -v python3 || true)
[[ -n "$PYTHON" ]] || die "Python 3 is required."

eval "$("$PYTHON" - "$STATE" <<'PY'
import json, shlex, sys
d=json.load(open(sys.argv[1]))
for key in ('runner','runner_backup','runtime_backup','config','config_backup'):
    print(f'{key.upper()}={shlex.quote(d.get(key, ""))}')
PY
)"

for system_dir in system32 syswow64; do
    [[ -d "$RUNTIME_BACKUP/$system_dir" ]] || continue
    for source in "$RUNTIME_BACKUP/$system_dir"/*.dll; do
        [[ -f "$source" ]] || continue
        cp -p "$source" "$PREFIX/drive_c/windows/$system_dir/$(basename "$source")"
    done
done

[[ -z "$CONFIG_BACKUP" || ! -f "$CONFIG_BACKUP" ]] || cp -p "$CONFIG_BACKUP" "$CONFIG"
rm -rf "$RUNNER"
[[ -z "$RUNNER_BACKUP" || ! -e "$RUNNER_BACKUP" ]] || mv "$RUNNER_BACKUP" "$RUNNER"
mv "$STATE" "$STATE.rolled-back-$(date '+%Y%m%d-%H%M%S')"

printf 'Rollback complete.\n'
