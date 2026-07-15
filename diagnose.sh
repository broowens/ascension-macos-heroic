#!/bin/bash
set -euo pipefail

HEROIC_ROOT="${HEROIC_ROOT:-$HOME/Games/Heroic}"
PREFIX=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX=$2; shift 2 ;;
        --help|-h) printf 'Usage: ./diagnose.sh [--prefix PATH]\n'; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PREFIX" ]]; then
    PREFIX=$(find "$HEROIC_ROOT/Prefixes" -type f -path '*/drive_c/Program Files/Ascension Launcher/resources/ascension-live/Ascension.exe' -print 2>/dev/null | sed 's#/drive_c/Program Files/Ascension Launcher/resources/ascension-live/Ascension.exe$##' | head -n 1)
fi

printf 'Project Ascension macOS diagnostics\n'
printf 'macOS: %s\n' "$(sw_vers -productVersion 2>/dev/null || echo unknown)"
printf 'CPU: %s\n' "$(uname -m)"
printf 'Prefix: %s\n' "${PREFIX:-not found}"

if [[ -z "$PREFIX" || ! -d "$PREFIX" ]]; then
    printf 'Result: Ascension prefix not found.\n'
    exit 1
fi

STATE="$PREFIX/.ascension-macos-fix/install.json"
if [[ -f "$STATE" ]]; then
    python3 - "$STATE" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
for key in ('version','runner','config','vc_version','installed_at'):
    print(f'{key.replace("_", " ").title()}: {d.get(key, "unknown")}')
PY
else
    printf 'Install state: missing\n'
fi

for arch_dir in syswow64 system32; do
    dll="$PREFIX/drive_c/windows/$arch_dir/msvcp140.dll"
    if [[ -f "$dll" ]]; then
        printf '%s MSVCP140: ' "$arch_dir"
        shasum -a 256 "$dll" | cut -d' ' -f1
    else
        printf '%s MSVCP140: missing\n' "$arch_dir"
    fi
done

GAME_DIR="$PREFIX/drive_c/Program Files/Ascension Launcher/resources/ascension-live"
if [[ -f "$GAME_DIR/MemoryBridge.log" ]]; then
    printf '\nRecent Memory Bridge entries:\n'
    tail -n 20 "$GAME_DIR/MemoryBridge.log" | sed -E 's/(password|token|login)[=:][^ ]+/\1=[REDACTED]/Ig'
fi

printf '\nProcesses: '
if pgrep -f 'Ascension Launcher\.exe|ascension-live.*Ascension\.exe|MMgr64\.exe' >/dev/null 2>&1; then
    printf 'Ascension processes are running (command lines intentionally hidden).\n'
else
    printf 'none.\n'
fi
