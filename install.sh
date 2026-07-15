#!/bin/bash
set -euo pipefail

VERSION="1.0.0"
RUNNER_NAME="WineCX26-RosettaX87-Mingw"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HEROIC_ROOT="${HEROIC_ROOT:-$HOME/Games/Heroic}"
RUNNER_ARCHIVE=""
REUSE_RUNNER=0
PREFIX=""
CONFIG=""

usage() {
    cat <<'EOF'
Usage: ./install.sh (--runner-archive PATH | --reuse-runner) [--prefix PATH] [--config PATH]

Options:
  --runner-archive PATH  Required prebuilt runner release archive.
  --reuse-runner         Use an already-installed compatibility runner.
  --prefix PATH          Ascension Wine prefix; auto-detected when omitted.
  --config PATH          Heroic GamesConfig JSON; auto-detected when omitted.
  --help                 Show this help.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '==> %s\n' "$*"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runner-archive) [[ $# -ge 2 ]] || die "Missing value for $1"; RUNNER_ARCHIVE=$2; shift 2 ;;
        --reuse-runner) REUSE_RUNNER=1; shift ;;
        --prefix) [[ $# -ge 2 ]] || die "Missing value for $1"; PREFIX=$2; shift 2 ;;
        --config) [[ $# -ge 2 ]] || die "Missing value for $1"; CONFIG=$2; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ $(uname -s) == Darwin ]] || die "This package supports macOS only."
[[ $(uname -m) == arm64 ]] || die "This package supports Apple Silicon only."
PYTHON=$(command -v python3 || true)
[[ -n "$PYTHON" ]] || die "Python 3 is required. Install it with: brew install python"
if [[ $REUSE_RUNNER -eq 1 ]]; then
    [[ -z "$RUNNER_ARCHIVE" ]] || die "Use either --runner-archive or --reuse-runner, not both."
else
    [[ -n "$RUNNER_ARCHIVE" ]] || die "--runner-archive or --reuse-runner is required."
    [[ -f "$RUNNER_ARCHIVE" ]] || die "Runner archive not found: $RUNNER_ARCHIVE"
fi

if pgrep -f '/Heroic.app/Contents/MacOS/Heroic|Ascension Launcher\.exe|ascension-live.*Ascension\.exe|MMgr64\.exe' >/dev/null 2>&1; then
    die "Close Heroic, Ascension Launcher, and Ascension before installing."
fi

if [[ -z "$PREFIX" ]]; then
    SEARCH_ROOT="$HEROIC_ROOT/Prefixes"
    [[ -d "$SEARCH_ROOT" ]] || die "Heroic prefix directory not found: $SEARCH_ROOT"
    PREFIX=$(
        find "$SEARCH_ROOT" -type f \
            -path '*/drive_c/Program Files/Ascension Launcher/resources/ascension-live/Ascension.exe' \
            -print 2>/dev/null | sed 's#/drive_c/Program Files/Ascension Launcher/resources/ascension-live/Ascension.exe$##' | head -n 1
    )
fi

[[ -n "$PREFIX" && -d "$PREFIX" ]] || die "Could not find the Ascension Wine prefix. Use --prefix."
GAME_DIR="$PREFIX/drive_c/Program Files/Ascension Launcher/resources/ascension-live"
[[ -f "$GAME_DIR/Ascension.exe" ]] || die "Ascension.exe not found in prefix: $PREFIX"

PACKAGE_CACHE="$PREFIX/drive_c/ProgramData/Package Cache"
[[ -d "$PACKAGE_CACHE" ]] || die "Microsoft VC++ package cache not found. Launch the Ascension installer once first."

VC_PATHS=$(
    "$PYTHON" "$SCRIPT_DIR/scripts/find_vc_runtime.py" "$PACKAGE_CACHE"
) || die "Could not locate matching x86 and x64 VC++ runtime packages."
VC_X86=$(printf '%s\n' "$VC_PATHS" | sed -n '1p')
VC_X64=$(printf '%s\n' "$VC_PATHS" | sed -n '2p')
VC_VERSION=$(printf '%s\n' "$VC_PATHS" | sed -n '3p')

RUNNERS_DIR="$HEROIC_ROOT/CustomRunners"
RUNNER_DIR="$RUNNERS_DIR/$RUNNER_NAME"
STAMP=$(date '+%Y%m%d-%H%M%S')
STATE_DIR="$PREFIX/.ascension-macos-fix"
BACKUP_DIR="$STATE_DIR/backups/$STAMP"
mkdir -p "$RUNNERS_DIR" "$BACKUP_DIR/system32" "$BACKUP_DIR/syswow64"

RUNNER_BACKUP=""
if [[ $REUSE_RUNNER -eq 0 ]]; then
    if [[ -e "$RUNNER_DIR" ]]; then
        RUNNER_BACKUP="$RUNNER_DIR.backup-$STAMP"
        log "Backing up existing custom runner"
        mv "$RUNNER_DIR" "$RUNNER_BACKUP"
    fi

    log "Installing custom runner"
    /usr/bin/tar -xf "$RUNNER_ARCHIVE" -C "$RUNNERS_DIR"
else
    log "Using installed custom runner"
fi
[[ -x "$RUNNER_DIR/bin/wine-heroic" ]] || die "Custom runner has an unexpected layout."
chmod +x "$RUNNER_DIR/bin/wine" "$RUNNER_DIR/bin/wine-heroic" \
    "$RUNNER_DIR/bin/wineserver" "$RUNNER_DIR/support/ascension-runtime/rosettax87"

# Keep Wine's core CRT available for wineboot, but force the game and its
# Memory Bridge to use the Microsoft MSVCP runtime installed below.
for rel in \
    i386-windows/msvcp140.dll \
    x86_64-windows/msvcp140.dll \
    x86_64-windows/msvcp140_1.dll \
    x86_64-windows/msvcp140_2.dll \
    x86_64-windows/msvcp140_atomic_wait.dll; do
    file="$RUNNER_DIR/lib/wine/$rel"
    [[ ! -f "$file" ]] || mv "$file" "$file.ascension-disabled"
done

log "Backing up prefix runtime DLLs"
for system_dir in system32 syswow64; do
    for dll in concrt140.dll msvcp140.dll msvcp140_1.dll msvcp140_2.dll \
        msvcp140_atomic_wait.dll msvcp140_codecvt_ids.dll vcruntime140.dll \
        vcruntime140_1.dll vcruntime140_threads.dll; do
        source="$PREFIX/drive_c/windows/$system_dir/$dll"
        [[ ! -f "$source" ]] || cp -p "$source" "$BACKUP_DIR/$system_dir/$dll"
    done
done

install_vc_cab() {
    local cab=$1
    local arch=$2
    local system_dir=$3
    local stage
    stage=$(mktemp -d "${TMPDIR:-/tmp}/ascension-vc.XXXXXX")
    /usr/bin/tar -xf "$cab" -C "$stage"
    for source in "$stage"/*_"$arch"; do
        [[ -f "$source" ]] || continue
        base=$(basename "$source" _"$arch")
        case "$base" in
            concrt140.dll|msvcp140.dll|msvcp140_1.dll|msvcp140_2.dll|msvcp140_atomic_wait.dll|msvcp140_codecvt_ids.dll|vcruntime140.dll|vcruntime140_1.dll|vcruntime140_threads.dll)
                install -m 0644 "$source" "$PREFIX/drive_c/windows/$system_dir/$base"
                ;;
        esac
    done
    rm -rf "$stage"
}

log "Installing Microsoft VC++ runtime $VC_VERSION from the local package cache"
install_vc_cab "$VC_X86" x86 syswow64
install_vc_cab "$VC_X64" amd64 system32

log "Updating Ascension's Heroic settings"
PATCH_OUTPUT=("$PYTHON" "$SCRIPT_DIR/scripts/patch_heroic_config.py" \
    --prefix "$PREFIX" --runner "$RUNNER_DIR" --stamp "$STAMP")
[[ -z "$CONFIG" ]] || PATCH_OUTPUT+=(--config "$CONFIG")
CONFIG_RESULT=$("${PATCH_OUTPUT[@]}")
CONFIG=$(printf '%s\n' "$CONFIG_RESULT" | sed -n '1p')
CONFIG_BACKUP=$(printf '%s\n' "$CONFIG_RESULT" | sed -n '2p')

log "Validating a cold Wine startup"
ENV_OVERRIDES='d3d9=n,b;DivxDecoder=b,n;msvcp140=n,b;vcruntime140=n,b;ucrtbase=n,b;concrt140=n,b;winemenubuilder.exe=d;mscoree=d;mshtml=d'
env WINEPREFIX="$PREFIX" WINEMSYNC=1 \
    ROSETTA_X87_PATH="$RUNNER_DIR/support/ascension-runtime/rosettax87" \
    ROSETTA_X87_EXTENDED_FPR_SCRATCH=1 \
    WINEDLLOVERRIDES="$ENV_OVERRIDES" WINEDEBUG=-all \
    "$RUNNER_DIR/bin/wine-heroic" wineboot -u >/dev/null 2>&1
WINEPREFIX="$PREFIX" "$RUNNER_DIR/bin/wineserver" -k >/dev/null 2>&1 || true

"$PYTHON" "$SCRIPT_DIR/scripts/write_state.py" \
    --output "$STATE_DIR/install.json" \
    --version "$VERSION" --prefix "$PREFIX" --runner "$RUNNER_DIR" \
    --runner-backup "$RUNNER_BACKUP" --runtime-backup "$BACKUP_DIR" \
    --config "$CONFIG" --config-backup "$CONFIG_BACKUP" --vc-version "$VC_VERSION"

log "Adding Project Ascension to Applications and Spotlight"
APP_ID=$(basename "$CONFIG" .json)
APP=$("$PYTHON" "$SCRIPT_DIR/scripts/register_macos_app.py" --app-id "$APP_ID")
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ ! -x "$LSREGISTER" ]] || "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true

printf '\nInstalled successfully.\n'
printf 'Prefix: %s\n' "$PREFIX"
printf 'Runner: %s\n' "$RUNNER_DIR"
printf 'VC++ runtime: %s\n' "$VC_VERSION"
printf 'Open Heroic and press Play, or launch Project Ascension from Spotlight.\n'
