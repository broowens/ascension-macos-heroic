#!/bin/bash
set -euo pipefail

VERSION="1.0.6"
RUNNER_VERSION="1.0.0"
RUNNER_ARCHIVE=""
LAUNCHER_INSTALLER=""
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST="$ROOT/dist"
RUNNER_NAME="WineCX26-RosettaX87-Mingw"
RUNNER_SHA256="da832e55fe008b4b317e70c9de8ea48d8a4e0d8cfb16ffa94bb6aaddb8152366"
LAUNCHER_URL="https://api.ascension.gg/api/v3/content/launcher/latest"

usage() {
    cat <<'EOF'
Usage: ./scripts/build-dmg.sh [options]

Options:
  --runner-archive PATH     Use an existing compatibility runner archive.
  --launcher-installer PATH Use an existing official Ascension setup executable.
  --version VERSION         Package version (default: 1.0.6).
  --help                    Show this help.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runner-archive) RUNNER_ARCHIVE=$2; shift 2 ;;
        --launcher-installer) LAUNCHER_INSTALLER=$2; shift 2 ;;
        --version) VERSION=$2; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ $(uname -s) == Darwin ]] || die "DMG builds require macOS."
for command in curl hdiutil codesign shasum python3 clang x86_64-w64-mingw32-gcc; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required."
done

RUNNER_ASSET="ascension-winecx26-rosettax87-mingw-v$RUNNER_VERSION.tar.xz"
RUNNER_URL="https://github.com/broowens/ascension-macos-heroic/releases/download/v$RUNNER_VERSION/$RUNNER_ASSET"

CACHE="$ROOT/.cache/dmg"
mkdir -p "$CACHE" "$DIST"

if [[ -z "$RUNNER_ARCHIVE" ]]; then
    RUNNER_ARCHIVE="$CACHE/$RUNNER_ASSET"
    if [[ ! -f "$RUNNER_ARCHIVE" ]]; then
        printf 'Downloading compatibility runtime...\n'
        curl -fL --retry 3 --progress-bar "$RUNNER_URL" -o "$RUNNER_ARCHIVE.part"
        mv "$RUNNER_ARCHIVE.part" "$RUNNER_ARCHIVE"
    fi
    actual=$(shasum -a 256 "$RUNNER_ARCHIVE" | awk '{print $1}')
    [[ "$actual" == "$RUNNER_SHA256" ]] || die "Compatibility runtime checksum mismatch."
fi
[[ -f "$RUNNER_ARCHIVE" ]] || die "Runner archive not found: $RUNNER_ARCHIVE"

if [[ -z "$LAUNCHER_INSTALLER" ]]; then
    LAUNCHER_INSTALLER="$CACHE/ascension-setup.exe"
    printf 'Downloading the official Ascension Launcher installer...\n'
    curl -fL --retry 3 --progress-bar "$LAUNCHER_URL" -o "$LAUNCHER_INSTALLER.part"
    mv "$LAUNCHER_INSTALLER.part" "$LAUNCHER_INSTALLER"
fi
[[ -s "$LAUNCHER_INSTALLER" ]] || die "Launcher installer not found: $LAUNCHER_INSTALLER"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/ascension-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Project Ascension.app"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES"

printf 'Assembling Project Ascension.app...\n'
cp -p "$ROOT/packaging/launch.sh" "$CONTENTS/MacOS/Project Ascension"
chmod +x "$CONTENTS/MacOS/Project Ascension"
cp -p "$LAUNCHER_INSTALLER" "$RESOURCES/ascension-setup.exe"
cp -p "$ROOT/LICENSE" "$RESOURCES/LICENSE"
cp -p "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto "$ROOT/packaging/runtime-patch" "$RESOURCES/runtime-patch"
cp -p "$ROOT/packaging/uninstall-app.sh" "$RESOURCES/ascension-uninstall.sh"
chmod +x "$RESOURCES/ascension-uninstall.sh"

MACOS_CC=$(command -v clang)
"$MACOS_CC" -fobjc-arc -Wall -Wextra -Os -arch x86_64 -mmacosx-version-min=12.0 \
    -dynamiclib -framework AppKit \
    "$ROOT/packaging/macos/ascension-settings.m" \
    "$ROOT/packaging/macos/ascension-menu.m" \
    -o "$RESOURCES/libascension-menu.dylib"
"$MACOS_CC" -fobjc-arc -Wall -Wextra -Os -arch arm64 -arch x86_64 \
    -mmacosx-version-min=12.0 -framework AppKit \
    "$ROOT/packaging/macos/ascension-settings.m" \
    "$ROOT/packaging/macos/ascension-settings-app.m" \
    -o "$RESOURCES/ascension-settings"
"$MACOS_CC" -fobjc-arc -Wall -Wextra -Os -arch arm64 \
    -mmacosx-version-min=12.0 -framework AppKit \
    "$ROOT/packaging/macos/ascension-progress.m" \
    -o "$RESOURCES/ascension-progress"

SETTINGS_APP="$RESOURCES/Ascension Settings.app"
mkdir -p "$SETTINGS_APP/Contents/MacOS"
cp -p "$RESOURCES/ascension-settings" "$SETTINGS_APP/Contents/MacOS/ascension-settings"
cat > "$SETTINGS_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Project Ascension Settings</string>
  <key>CFBundleExecutable</key><string>ascension-settings</string>
  <key>CFBundleIdentifier</key><string>com.broowens.project-ascension.settings</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Project Ascension Settings</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

WINDOW_CC=$(command -v x86_64-w64-mingw32-gcc)
"$WINDOW_CC" -std=c11 -Wall -Wextra -Werror -Os -s -shared \
    "$ROOT/packaging/window-controls/ascension-window-hook.c" \
    -o "$RESOURCES/ascension-window-hook.dll"
"$WINDOW_CC" -std=c11 -Wall -Wextra -Werror -Os -s -mwindows \
    "$ROOT/packaging/window-controls/ascension-window-controls.c" \
    -o "$RESOURCES/ascension-window-controls.exe"

/usr/bin/tar -xf "$RUNNER_ARCHIVE" -C "$RESOURCES"
[[ -x "$RESOURCES/$RUNNER_NAME/bin/wine-heroic" ]] || die "Runner archive has an unexpected layout."

# The sanitized release replaces its original compiled install path with a
# same-length placeholder. Retarget every embedded Wine path to a short,
# stable location that the app populates on first launch.
python3 - "$RESOURCES/$RUNNER_NAME" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
base = b"/Users/Shared/PAWine"
replacements = {
    b"/xxxxxxxxxxxxxxxxx/Games/Heroic/CustomRunners/WineCX26-RosettaX87-Mingw/bin": base + b"/bin",
    b"/xxxxxxxxxxxxxxxxx/Games/Heroic/CustomRunners/WineCX26-RosettaX87-Mingw/lib": base + b"/lib",
    b"/xxxxxxxxxxxxxxxxx/Games/Heroic/CustomRunners/WineCX26-RosettaX87-Mingw/share/wine/nls": base + b"/share/wine/nls",
    b"/opt/stuff/wine/target/bin": base + b"/bin",
    b"/opt/stuff/wine/target/lib/wine": base + b"/lib/wine",
    b"/opt/stuff/wine/target/share/wine": base + b"/share/wine",
    b"/tmp/heroic-cx-alt-loader-501.sock": b"/tmp/ascension-pa.sock",
}
counts = {old: 0 for old in replacements}
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    data = path.read_bytes()
    changed = data
    for old, new in replacements.items():
        if len(new) > len(old):
            raise SystemExit(f"Replacement path is too long: {new!r}")
        count = changed.count(old)
        if count:
            changed = changed.replace(old, new + (b"\0" * (len(old) - len(new))))
            counts[old] += count
    if changed != data:
        path.write_bytes(changed)

required = [old for old in replacements if old.startswith(b"/xxxxxxxx")]
missing = [old.decode() for old in required if counts[old] == 0]
if missing:
    raise SystemExit(f"Runner did not contain expected relocatable paths: {missing}")
PY

# Do not share the alternate-loader socket with Heroic or another installed
# runner. A stale broker would otherwise launch 32-bit processes through the
# wrong (or removed) Wine installation.
sed -i '' \
    's#/tmp/heroic-cx-alt-loader-${UID}.sock#/tmp/ascension-pa.sock#' \
    "$RESOURCES/$RUNNER_NAME/bin/wine-heroic"

# macOS strips DYLD_* variables before executing scripts whose interpreter is
# a protected system shell. Carry the library path under an app-specific name,
# then export it from inside the runner immediately before Wine is executed.
python3 - "$RESOURCES/$RUNNER_NAME/bin/wine-heroic" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = 'export DYLD_FALLBACK_LIBRARY_PATH="$runner_dir/../lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"\n'
addition = (
    needle
    + 'if [[ -n "${ASCENSION_DYLD_INSERT_LIBRARIES:-}" ]]; then\n'
    + '    export DYLD_INSERT_LIBRARIES="$ASCENSION_DYLD_INSERT_LIBRARIES"\n'
    + 'fi\n'
)
if needle not in text:
    raise SystemExit("Runner wrapper did not contain the expected library-path export")
path.write_text(text.replace(needle, addition, 1))
PY

# zsh starts background jobs at nice 5 by default. Disable that behavior before
# starting the alternate-loader broker, detach with an ignored SIGHUP, and
# retire an older nice-5 broker once no game is using it.
python3 - "$RESOURCES/$RUNNER_NAME/bin/wine-heroic" \
    "$RESOURCES/$RUNNER_NAME/bin/cx-alt-loader.py" <<'PY'
from pathlib import Path
import sys

wrapper = Path(sys.argv[1])
wrapper_text = wrapper.read_text()
shebang = "#!/bin/zsh\n"
priority_setup = (
    shebang
    + "\n"
    + "# zsh otherwise starts background jobs at nice 5. The alternate-loader broker\n"
    + "# passes that lower scheduling priority to every Wine process it creates.\n"
    + "unsetopt BG_NICE\n"
)
if shebang not in wrapper_text:
    raise SystemExit("Runner wrapper did not contain the expected shebang")
wrapper_text = wrapper_text.replace(shebang, priority_setup, 1)
pid_path_needle = 'pid_path="${socket_path}.pid"\n'
if pid_path_needle not in wrapper_text:
    raise SystemExit("Runner wrapper did not contain the expected pid path")
wrapper_text = wrapper_text.replace(
    pid_path_needle,
    pid_path_needle + 'lock_path="${socket_path}.lock"\n',
    1,
)
old_wrapper = '''if [[ ! -S "$socket_path" ]] || ! kill -0 "$(<"$pid_path")" 2>/dev/null; then
    rm -f "$socket_path" "$pid_path"
    /usr/bin/nohup "$python_bin" "$runner_dir/cx-alt-loader.py" \\
        --socket "$socket_path" --wine "$runner_dir/wine" >"$log_path" 2>&1 &
    print $! >"$pid_path"
    for _ in {1..50}; do
        [[ -S "$socket_path" ]] && break
        sleep 0.02
    done
fi
'''
new_wrapper = '''acquire_broker_lock() {
    for _ in {1..250}; do
        /usr/bin/shlock -f "$lock_path" -p $$ && return 0
        sleep 0.02
    done
    return 1
}

release_broker_lock() {
    if [[ -r "$lock_path" && "$(<"$lock_path")" == "$$" ]]; then
        rm -f "$lock_path"
    fi
}

if ! acquire_broker_lock; then
    print -u2 "Timed out waiting for the alternate-loader startup lock"
    exit 1
fi
trap release_broker_lock EXIT HUP INT TERM

daemon_pid=""
if [[ -r "$pid_path" ]]; then
    daemon_pid=$(<"$pid_path")
fi

game_is_running() {
    /bin/ps -axo state=,command= | /usr/bin/awk \\
        '$1 !~ /Z/ && $0 ~ /[A]scension[.]exe/ { found = 1 } END { exit found ? 0 : 1 }'
}

# A previous unlocked startup may have created multiple brokers. Once no game
# is using them, retire every broker except the one recorded in the pid file.
if ! game_is_running; then
    for broker_pid in $(/usr/bin/pgrep -f '[c]x-alt-loader.py --socket /tmp/ascension-pa.sock' || true); do
        if [[ "$broker_pid" != "$daemon_pid" ]]; then
            kill "$broker_pid" 2>/dev/null || true
        fi
    done
fi

# Replace a broker created before BG_NICE was disabled only when Ascension is
# not running; never disturb an active game session.
if [[ -n "$daemon_pid" && -S "$socket_path" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
    daemon_nice=$(/bin/ps -o nice= -p "$daemon_pid" 2>/dev/null)
    daemon_nice=${daemon_nice//[[:space:]]/}
    if [[ "$daemon_nice" != "0" ]] && ! game_is_running; then
        kill "$daemon_pid" 2>/dev/null || true
        for _ in {1..50}; do
            ! kill -0 "$daemon_pid" 2>/dev/null && break
            sleep 0.02
        done
        if ! kill -0 "$daemon_pid" 2>/dev/null; then
            rm -f "$socket_path" "$pid_path"
            daemon_pid=""
        fi
    fi
fi

if [[ -z "$daemon_pid" || ! -S "$socket_path" ]] || ! kill -0 "$daemon_pid" 2>/dev/null; then
    rm -f "$socket_path" "$pid_path"
    "$python_bin" "$runner_dir/cx-alt-loader.py" \\
        --socket "$socket_path" --wine "$runner_dir/wine" >"$log_path" 2>&1 &
    daemon_pid=$!
    print "$daemon_pid" >"$pid_path"
    for _ in {1..50}; do
        [[ -S "$socket_path" ]] && break
        sleep 0.02
    done
fi

if [[ ! -S "$socket_path" ]]; then
    print -u2 "The alternate-loader broker did not create its socket"
    exit 1
fi

release_broker_lock
trap - EXIT HUP INT TERM
'''
if old_wrapper not in wrapper_text:
    raise SystemExit("Runner wrapper did not contain the expected broker launch block")
wrapper.write_text(wrapper_text.replace(old_wrapper, new_wrapper, 1))

loader = Path(sys.argv[2])
loader_text = loader.read_text()
import_needle = "import os\nimport socket\n"
if import_needle not in loader_text:
    raise SystemExit("Alternate loader did not contain the expected imports")
loader_text = loader_text.replace(import_needle, "import os\nimport signal\nimport socket\n", 1)
serve_needle = "    args = parser.parse_args()\n    serve(args.socket, args.wine)\n"
if serve_needle not in loader_text:
    raise SystemExit("Alternate loader did not contain the expected entry point")
loader_text = loader_text.replace(
    serve_needle,
    "    args = parser.parse_args()\n"
    "    signal.signal(signal.SIGHUP, signal.SIG_IGN)\n"
    "    serve(args.socket, args.wine)\n",
    1,
)
loader.write_text(loader_text)
PY

# Reuse the official launcher's own artwork for the macOS app icon.
ICON_STAGE="$STAGE/icon-source"
ICONSET="$STAGE/ProjectAscension.iconset"
mkdir -p "$ICON_STAGE" "$ICONSET"
if /usr/bin/tar -xf "$LAUNCHER_INSTALLER" -C "$ICON_STAGE" resources/app-icon.ico 2>/dev/null; then
    for spec in '16 icon_16x16.png' '32 icon_16x16@2x.png' \
        '32 icon_32x32.png' '64 icon_32x32@2x.png' \
        '128 icon_128x128.png' '256 icon_128x128@2x.png' \
        '256 icon_256x256.png' '512 icon_256x256@2x.png' \
        '512 icon_512x512.png' '1024 icon_512x512@2x.png'; do
        size=${spec%% *}
        name=${spec#* }
        sips -s format png -z "$size" "$size" "$ICON_STAGE/resources/app-icon.ico" \
            --out "$ICONSET/$name" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$RESOURCES/ProjectAscension.icns"
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Project Ascension</string>
  <key>CFBundleExecutable</key><string>Project Ascension</string>
  <key>CFBundleIdentifier</key><string>com.broowens.project-ascension</string>
  <key>CFBundleIconFile</key><string>ProjectAscension</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Project Ascension</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
</dict>
</plist>
EOF

cat > "$RESOURCES/PACKAGE-MANIFEST.txt" <<EOF
Project Ascension for Mac $VERSION
Official launcher installer SHA-256: $(shasum -a 256 "$LAUNCHER_INSTALLER" | awk '{print $1}')
Compatibility runtime SHA-256: $(shasum -a 256 "$RUNNER_ARCHIVE" | awk '{print $1}')
Game data included: no
Window close-control compatibility helper: included
Native macOS settings and application menu: included
Native first-launch setup progress: included
Configurable DXVK performance overlay: included
EOF

# Ad-hoc signing validates the app structure for local distribution. A public,
# warning-free release should replace '-' with an Apple Developer ID identity
# and be notarized after the DMG is created.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

DMG_ROOT="$STAGE/dmg"
mkdir -p "$DMG_ROOT"
/usr/bin/ditto "$APP" "$DMG_ROOT/Project Ascension.app"
ln -s /Applications "$DMG_ROOT/Applications"

DMG="$DIST/Project-Ascension-for-Mac-v$VERSION.dmg"
rm -f "$DMG"
printf 'Creating compressed DMG...\n'
hdiutil create -quiet -volname "Project Ascension" -srcfolder "$DMG_ROOT" \
    -format UDZO -imagekey zlib-level=9 -ov "$DMG"

(
    cd "$DIST"
    shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
)
printf '\nCreated:\n'
ls -lh "$DMG" "$DMG.sha256"
