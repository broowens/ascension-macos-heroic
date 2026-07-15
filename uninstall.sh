#!/bin/bash
set -euo pipefail

REPOSITORY="broowens/ascension-macos-heroic"
RUNNER_NAME="WineCX26-RosettaX87-Mingw"
HEROIC_ROOT="${HEROIC_ROOT:-$HOME/Games/Heroic}"
HEROIC_DATA="${HEROIC_DATA:-$HOME/Library/Application Support/heroic}"
PREFIX=""
ASSUME_YES=0
REMOVE_HEROIC=0
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
CACHE_DIR="$HOME/Library/Caches/ascension-macos-heroic"
APP="$HOME/Applications/Project Ascension.app"

usage() {
    cat <<'EOF'
Usage: ./uninstall.sh [options]

Removes Project Ascension, its Heroic registration, compatibility runner,
installer cache, and macOS application shortcut.

Options:
  --prefix PATH       Ascension Wine prefix; auto-detected when omitted.
  --heroic-root PATH  Heroic games directory (default: ~/Games/Heroic).
  --remove-heroic     Also remove Heroic.app (Heroic data and other games remain).
  --yes               Do not ask for confirmation.
  --help              Show this help.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }

# Support the same curl-to-bash workflow as bootstrap.sh by staging the package
# when this script has no neighbouring helper files.
if [[ ! -f "$SCRIPT_DIR/scripts/unregister_heroic_game.py" ]]; then
    STAGE=$(mktemp -d "${TMPDIR:-/tmp}/ascension-uninstall.XXXXXX")
    trap 'rm -rf "$STAGE"' EXIT
    log "Downloading the uninstaller package"
    if ! curl -fL --retry 3 --progress-bar \
        "https://github.com/$REPOSITORY/archive/refs/heads/main.tar.gz" \
        -o "$STAGE/package.tar.gz"; then
        command -v gh >/dev/null 2>&1 || die "The repository is not public and GitHub CLI is unavailable."
        gh api "repos/$REPOSITORY/tarball/main" > "$STAGE/package.tar.gz"
    fi
    /usr/bin/tar -xzf "$STAGE/package.tar.gz" -C "$STAGE"
    STAGED_SCRIPT=$(find "$STAGE" -mindepth 2 -maxdepth 2 -name uninstall.sh -print | head -n 1)
    [[ -n "$STAGED_SCRIPT" ]] || die "Downloaded package did not contain uninstall.sh."
    "$STAGED_SCRIPT" "$@"
    exit $?
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) [[ $# -ge 2 ]] || die "Missing value for $1"; PREFIX=$2; shift 2 ;;
        --heroic-root) [[ $# -ge 2 ]] || die "Missing value for $1"; HEROIC_ROOT=$2; shift 2 ;;
        --remove-heroic) REMOVE_HEROIC=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ $(uname -s) == Darwin ]] || die "This uninstaller supports macOS only."
PYTHON=$(command -v python3 || true)
[[ -n "$PYTHON" ]] || die "Python 3 is required to update Heroic safely."

if pgrep -f '/Heroic.app/Contents/MacOS/Heroic|Ascension Launcher\.exe|ascension-live.*Ascension\.exe|MMgr64\.exe' >/dev/null 2>&1; then
    die "Close Heroic, Ascension Launcher, and Ascension before uninstalling."
fi

if [[ -z "$PREFIX" && -d "$HEROIC_ROOT/Prefixes" ]]; then
    PREFIX=$(find "$HEROIC_ROOT/Prefixes" -type f \
        -path '*/drive_c/Program Files/Ascension Launcher/Ascension Launcher.exe' \
        -print 2>/dev/null | sed 's#/drive_c/Program Files/Ascension Launcher/Ascension Launcher.exe$##' | sed -n '1p')
fi
[[ -n "$PREFIX" ]] || PREFIX="$HEROIC_ROOT/Prefixes/Project Ascension"

case "$PREFIX" in
    /|"$HOME"|"$HEROIC_ROOT"|"$HEROIC_ROOT/Prefixes")
        die "Refusing unsafe prefix path: $PREFIX"
        ;;
esac
if [[ -e "$PREFIX" \
    && ! -f "$PREFIX/.ascension-macos-fix/install.json" \
    && ! -f "$PREFIX/drive_c/Program Files/Ascension Launcher/Ascension Launcher.exe" ]]; then
    die "The selected prefix does not contain Project Ascension: $PREFIX"
fi

printf 'This will permanently remove:\n'
printf '  Prefix: %s\n' "$PREFIX"
printf '  Runner: %s/CustomRunners/%s\n' "$HEROIC_ROOT" "$RUNNER_NAME"
printf '  Heroic registration, installer cache, and %s\n' "$APP"
if [[ $REMOVE_HEROIC -eq 1 ]]; then
    printf '  Heroic.app from ~/Applications or /Applications\n'
fi
printf 'Heroic data for other games, Homebrew, and Python will be kept.\n'

if [[ $ASSUME_YES -eq 0 ]]; then
    [[ -t 0 ]] || die "Confirmation requires a terminal. Rerun with --yes."
    read -r -p 'Continue? [y/N] ' answer
    [[ "$answer" == y || "$answer" == Y || "$answer" == yes || "$answer" == YES ]] || {
        printf 'Uninstall cancelled.\n'
        exit 0
    }
fi

log "Removing Project Ascension from Heroic"
"$PYTHON" "$SCRIPT_DIR/scripts/unregister_heroic_game.py" \
    --prefix "$PREFIX" --heroic-data "$HEROIC_DATA"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ ! -x "$LSREGISTER" ]] || "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true

log "Removing Project Ascension files"
rm -rf "$PREFIX" "$HEROIC_ROOT/CustomRunners/$RUNNER_NAME" "$CACHE_DIR" "$APP"

if [[ $REMOVE_HEROIC -eq 1 ]]; then
    rm -rf "$HOME/Applications/Heroic.app"
    if [[ -d "/Applications/Heroic.app" ]]; then
        log "Removing Heroic from /Applications (administrator approval may be required)"
        sudo rm -rf "/Applications/Heroic.app"
    fi
fi

printf '\nUninstall complete.\n'
