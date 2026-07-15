#!/bin/bash
set -euo pipefail

VERSION="1.0.0"
REPOSITORY="broowens/ascension-macos-heroic"
RUNNER_NAME="WineCX26-RosettaX87-Mingw"
HEROIC_ROOT="${HEROIC_ROOT:-$HOME/Games/Heroic}"
HEROIC_DATA="${HEROIC_DATA:-$HOME/Library/Application Support/heroic}"
PREFIX=""
DRY_RUN=0
SKIP_HEROIC=0
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
CACHE_DIR="$HOME/Library/Caches/ascension-macos-heroic"

usage() {
    cat <<'EOF'
Usage: ./bootstrap.sh [options]

Installs Heroic, Project Ascension, the custom runner, and the macOS
compatibility settings. The official Ascension windows remain interactive.

Options:
  --prefix PATH       Wine prefix to create or reuse.
  --heroic-root PATH  Heroic games directory (default: ~/Games/Heroic).
  --skip-heroic       Do not install Heroic Games Launcher.
  --dry-run           Show detected state without changing anything.
  --help              Show this help.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }

# A raw `curl | bash` invocation has no neighbouring repository files. Stage a
# clean copy of main, then hand the original arguments to that copy.
if [[ ! -f "$SCRIPT_DIR/install.sh" ]]; then
    STAGE=$(mktemp -d "${TMPDIR:-/tmp}/ascension-bootstrap.XXXXXX")
    trap 'rm -rf "$STAGE"' EXIT
    log "Downloading the installer package"
    if ! curl -fL --retry 3 --progress-bar \
        "https://github.com/$REPOSITORY/archive/refs/heads/main.tar.gz" \
        -o "$STAGE/package.tar.gz"; then
        command -v gh >/dev/null 2>&1 || die "The repository is not public and GitHub CLI is unavailable."
        gh api "repos/$REPOSITORY/tarball/main" > "$STAGE/package.tar.gz"
    fi
    /usr/bin/tar -xzf "$STAGE/package.tar.gz" -C "$STAGE"
    STAGED_SCRIPT=$(find "$STAGE" -mindepth 2 -maxdepth 2 -name bootstrap.sh -print | head -n 1)
    [[ -n "$STAGED_SCRIPT" ]] || die "Downloaded package did not contain bootstrap.sh."
    "$STAGED_SCRIPT" "$@"
    exit $?
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) [[ $# -ge 2 ]] || die "Missing value for $1"; PREFIX=$2; shift 2 ;;
        --heroic-root) [[ $# -ge 2 ]] || die "Missing value for $1"; HEROIC_ROOT=$2; shift 2 ;;
        --skip-heroic) SKIP_HEROIC=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ $(uname -s) == Darwin ]] || die "This installer supports macOS only."
[[ $(uname -m) == arm64 ]] || die "This installer supports Apple Silicon only."

if pgrep -f '/Heroic.app/Contents/MacOS/Heroic|Ascension Launcher\.exe|ascension-live.*Ascension\.exe|MMgr64\.exe' >/dev/null 2>&1; then
    die "Close Heroic, Ascension Launcher, and Ascension before continuing."
fi

if [[ -z "$PREFIX" ]]; then
    if [[ -d "$HEROIC_ROOT/Prefixes" ]]; then
        PREFIX=$(
            find "$HEROIC_ROOT/Prefixes" -type f \
                -path '*/drive_c/Program Files/Ascension Launcher/Ascension Launcher.exe' \
                -print 2>/dev/null | sed 's#/drive_c/Program Files/Ascension Launcher/Ascension Launcher.exe$##' | sed -n '1p'
        )
    fi
    [[ -n "$PREFIX" ]] || PREFIX="$HEROIC_ROOT/Prefixes/Project Ascension"
fi

RUNNERS_DIR="$HEROIC_ROOT/CustomRunners"
RUNNER_DIR="$RUNNERS_DIR/$RUNNER_NAME"
LAUNCHER_DIR="$PREFIX/drive_c/Program Files/Ascension Launcher"
LAUNCHER="$LAUNCHER_DIR/Ascension Launcher.exe"
GAME="$LAUNCHER_DIR/resources/ascension-live/Ascension.exe"
STATE="$PREFIX/.ascension-macos-fix/install.json"

if [[ $DRY_RUN -eq 1 ]]; then
    printf 'Heroic app: %s\n' "$(find /Applications "$HOME/Applications" -maxdepth 1 -name Heroic.app -print 2>/dev/null | head -n 1 || true)"
    printf 'Heroic root: %s\n' "$HEROIC_ROOT"
    printf 'Prefix: %s (%s)\n' "$PREFIX" "$([[ -d "$PREFIX" ]] && echo present || echo missing)"
    printf 'Runner: %s (%s)\n' "$RUNNER_DIR" "$([[ -x "$RUNNER_DIR/bin/wine-heroic" ]] && echo present || echo missing)"
    printf 'Launcher: %s\n' "$([[ -f "$LAUNCHER" ]] && echo present || echo missing)"
    printf 'Game: %s\n' "$([[ -f "$GAME" ]] && echo present || echo missing)"
    printf 'Compatibility fix: %s\n' "$([[ -f "$STATE" ]] && echo installed || echo missing)"
    exit 0
fi

ensure_python() {
    if command -v python3 >/dev/null 2>&1; then
        return
    fi

    local brew_bin
    brew_bin=$(command -v brew || true)
    if [[ -z "$brew_bin" ]]; then
        log "Installing Homebrew (needed to install Python 3)"
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        brew_bin=/opt/homebrew/bin/brew
    fi
    [[ -x "$brew_bin" ]] || die "Homebrew installation did not provide a brew command."
    log "Installing Python 3"
    "$brew_bin" install python
    export PATH="/opt/homebrew/bin:$PATH"
    command -v python3 >/dev/null 2>&1 || die "Python 3 installation failed."
}

github_asset() {
    local repository=$1
    local release=$2
    local pattern=$3
    local metadata=$4
    local endpoint="https://api.github.com/repos/$repository/releases/$release"
    if ! curl -fsSL --retry 3 "$endpoint" -o "$metadata"; then
        command -v gh >/dev/null 2>&1 || die "Could not read release metadata for $repository."
        gh api "repos/$repository/releases/$release" > "$metadata"
    fi
    python3 - "$metadata" "$pattern" <<'PY'
import fnmatch, json, sys

document = json.load(open(sys.argv[1]))
matches = [asset for asset in document.get("assets", []) if fnmatch.fnmatch(asset.get("name", ""), sys.argv[2])]
if len(matches) != 1:
    raise SystemExit(f"Expected one release asset matching {sys.argv[2]!r}, found {len(matches)}")
print(matches[0]["browser_download_url"])
digest = matches[0].get("digest") or ""
print(digest[7:] if digest.startswith("sha256:") else digest)
print(matches[0]["url"])
PY
}

download_verified() {
    local url=$1
    local destination=$2
    local digest=$3
    local api_url=${4:-}
    local temporary="$destination.part"
    mkdir -p "$(dirname "$destination")"
    if ! curl -fL --retry 3 --progress-bar "$url" -o "$temporary"; then
        [[ -n "$api_url" ]] || die "Could not download $(basename "$destination")."
        command -v gh >/dev/null 2>&1 || die "The release is private and GitHub CLI is unavailable."
        gh api -H 'Accept: application/octet-stream' "$api_url" > "$temporary"
    fi
    if [[ -n "$digest" ]]; then
        local actual
        actual=$(shasum -a 256 "$temporary" | awk '{print $1}')
        [[ "$actual" == "$digest" ]] || die "Checksum mismatch for $(basename "$destination")."
    fi
    mv "$temporary" "$destination"
}

ensure_heroic() {
    local heroic_app
    heroic_app=$(find /Applications "$HOME/Applications" -maxdepth 1 -name Heroic.app -print 2>/dev/null | head -n 1 || true)
    if [[ -n "$heroic_app" ]]; then
        log "Heroic is already installed"
        return
    fi
    [[ $SKIP_HEROIC -eq 0 ]] || die "Heroic is missing and --skip-heroic was used."

    log "Downloading the latest Heroic release"
    local metadata asset_info url digest api_url dmg mount
    metadata=$(mktemp "${TMPDIR:-/tmp}/heroic-release.XXXXXX")
    asset_info=$(github_asset "Heroic-Games-Launcher/HeroicGamesLauncher" "latest" 'Heroic-*-macOS-arm64.dmg' "$metadata")
    rm -f "$metadata"
    url=$(printf '%s\n' "$asset_info" | sed -n '1p')
    digest=$(printf '%s\n' "$asset_info" | sed -n '2p')
    api_url=$(printf '%s\n' "$asset_info" | sed -n '3p')
    dmg="$CACHE_DIR/$(basename "$url")"
    download_verified "$url" "$dmg" "$digest" "$api_url"

    log "Installing Heroic in your Applications folder"
    mount=$(mktemp -d "${TMPDIR:-/tmp}/heroic-mount.XXXXXX")
    hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$dmg" >/dev/null
    mkdir -p "$HOME/Applications"
    /usr/bin/ditto "$mount/Heroic.app" "$HOME/Applications/Heroic.app"
    hdiutil detach "$mount" >/dev/null
    rmdir "$mount"
}

ensure_runner() {
    if [[ -x "$RUNNER_DIR/bin/wine-heroic" ]]; then
        log "The Ascension custom runner is already installed"
        return
    fi

    log "Downloading compatibility runner v$VERSION"
    local metadata asset_info url digest api_url archive first_entry
    metadata=$(mktemp "${TMPDIR:-/tmp}/ascension-release.XXXXXX")
    asset_info=$(github_asset "$REPOSITORY" "tags/v$VERSION" "ascension-winecx26-rosettax87-mingw-v$VERSION.tar.xz" "$metadata")
    rm -f "$metadata"
    url=$(printf '%s\n' "$asset_info" | sed -n '1p')
    digest=$(printf '%s\n' "$asset_info" | sed -n '2p')
    api_url=$(printf '%s\n' "$asset_info" | sed -n '3p')
    archive="$CACHE_DIR/$(basename "$url")"
    download_verified "$url" "$archive" "$digest" "$api_url"

    first_entry=$(/usr/bin/tar -tf "$archive" | sed -n '1p')
    [[ "$first_entry" == "$RUNNER_NAME" || "$first_entry" == "$RUNNER_NAME/" ]] || die "Runner archive has an unexpected layout."
    /usr/bin/tar -tf "$archive" | while IFS= read -r entry; do
        [[ "$entry" != /* && "$entry" != *'../'* ]] || die "Unsafe path in runner archive."
    done
    mkdir -p "$RUNNERS_DIR"
    /usr/bin/tar -xf "$archive" -C "$RUNNERS_DIR"
    chmod +x "$RUNNER_DIR/bin/wine" "$RUNNER_DIR/bin/wine-heroic" \
        "$RUNNER_DIR/bin/wineserver" "$RUNNER_DIR/support/ascension-runtime/rosettax87"
    [[ -x "$RUNNER_DIR/bin/wine-heroic" ]] || die "Custom runner installation failed."
}

wine_env() {
    env WINEPREFIX="$PREFIX" WINEMSYNC=1 \
        ROSETTA_X87_PATH="$RUNNER_DIR/support/ascension-runtime/rosettax87" \
        ROSETTA_X87_EXTENDED_FPR_SCRATCH=1 \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' WINEDEBUG=-all "$@"
}

ensure_prefix() {
    if [[ -f "$PREFIX/system.reg" ]]; then
        return
    fi
    log "Creating the Ascension Wine prefix"
    mkdir -p "$PREFIX"
    wine_env "$RUNNER_DIR/bin/wine-heroic" wineboot -u
    WINEPREFIX="$PREFIX" "$RUNNER_DIR/bin/wineserver" -k >/dev/null 2>&1 || true
}

ensure_launcher() {
    [[ ! -f "$LAUNCHER" ]] || return
    log "Downloading the official Project Ascension installer"
    local setup="$CACHE_DIR/ascension-setup.exe"
    mkdir -p "$CACHE_DIR"
    curl -fL --retry 3 --progress-bar \
        "https://api.ascension.gg/api/v3/content/launcher/latest" -o "$setup.part"
    mv "$setup.part" "$setup"

    log "Complete the official Ascension Launcher setup window"
    wine_env "$RUNNER_DIR/bin/wine-heroic" "$setup"
    WINEPREFIX="$PREFIX" "$RUNNER_DIR/bin/wineserver" -w >/dev/null 2>&1 || true
    [[ -f "$LAUNCHER" ]] || die "Ascension Launcher was not installed. Rerun this command to resume."
}

ensure_game() {
    [[ ! -f "$GAME" ]] || return
    log "Install Project Ascension in the launcher, then close the launcher"
    printf 'The game download is large. This terminal will continue when the launcher closes.\n'
    wine_env "$RUNNER_DIR/bin/wine-heroic" "$LAUNCHER" \
        --no-sandbox --disable-gpu-sandbox --disable-gpu --use-angle=swiftshader
    WINEPREFIX="$PREFIX" "$RUNNER_DIR/bin/wineserver" -w >/dev/null 2>&1 || true
    [[ -f "$GAME" ]] || die "The game download is not complete. Rerun this command to resume."
}

ensure_python
ensure_heroic
ensure_runner
ensure_prefix
ensure_launcher
ensure_game

log "Registering Project Ascension in Heroic"
CONFIG=$(python3 "$SCRIPT_DIR/scripts/register_heroic_game.py" \
    --prefix "$PREFIX" --heroic-data "$HEROIC_DATA")

if [[ -f "$STATE" ]]; then
    log "The Ascension compatibility fix is already installed"
else
    log "Applying the Ascension compatibility fix"
    "$SCRIPT_DIR/install.sh" --reuse-runner --prefix "$PREFIX" --config "$CONFIG"
fi

log "Installation complete"
printf 'Project Ascension is ready in Heroic.\n'
printf 'Prefix: %s\n' "$PREFIX"
printf 'You can now open Heroic and press Play.\n'
