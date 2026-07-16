#!/bin/bash
set -euo pipefail

VERSION="1.0.0"
RUNNER=""
SOURCE_ARCHIVE=""
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST="$ROOT/dist"

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runner) RUNNER=$2; shift 2 ;;
        --source-archive) SOURCE_ARCHIVE=$2; shift 2 ;;
        --version) VERSION=$2; shift 2 ;;
        --help|-h)
            printf 'Usage: %s --runner PATH --source-archive PATH [--version VERSION]\n' "$0"
            exit 0
            ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ -x "$RUNNER/bin/wine-heroic" ]] || die "Invalid runner: $RUNNER"
[[ -f "$SOURCE_ARCHIVE" ]] || die "Source archive not found: $SOURCE_ARCHIVE"
PYTHON=$(command -v python3 || true)
[[ -n "$PYTHON" ]] || die "Python 3 is required."

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/ascension-runner-release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
NAME="WineCX26-RosettaX87-Mingw"
TARGET="$STAGE/$NAME"
mkdir -p "$TARGET/support/ascension-runtime" "$DIST"

for directory in bin lib share; do
    /usr/bin/rsync -a \
        --exclude='.codex-*' --exclude='*.codex-*' --exclude='*.ascension-disabled' \
        --exclude='*.pre-*' "$RUNNER/$directory/" "$TARGET/$directory/"
done
cp -p "$RUNNER/support/ascension-runtime/rosettax87" "$TARGET/support/ascension-runtime/"
cp -p "$RUNNER/support/ascension-runtime/libRuntimeRosettax87" "$TARGET/support/ascension-runtime/"

if find "$TARGET" -type f \( -iname 'Ascension.exe' -o -iname 'MMgr64.exe' -o -iname 'DivxDecoderOriginal.dll' -o -iname 'Extensions.dll' \) | grep -q .; then
    die "A Project Ascension binary entered the release stage."
fi
"$ROOT/scripts/audit-runner.sh" "$TARGET" "$SOURCE_ARCHIVE"

# Strip debug tables to reduce the release and remove local build paths.
for directory in i386-windows x86_64-windows; do
    strip_tool=i686-w64-mingw32-strip
    [[ "$directory" == x86_64-windows ]] && strip_tool=x86_64-w64-mingw32-strip
    if command -v "$strip_tool" >/dev/null 2>&1; then
        find "$TARGET/lib/wine/$directory" -type f -print0 | while IFS= read -r -d '' file; do
            "$strip_tool" --strip-debug "$file" >/dev/null 2>&1 || true
        done
    fi
done

# Replace the builder's home path byte-for-byte. The Rosetta path is always
# supplied by the installer, so its compiled fallback must never be used.
"$PYTHON" - "$TARGET" "$HOME" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
old = sys.argv[2].encode()
replacement = b"/" + (b"x" * (len(old) - 1))
for path in root.rglob("*"):
    if not path.is_file():
        continue
    data = path.read_bytes()
    if old in data:
        path.write_bytes(data.replace(old, replacement))
PY

if rg -a -q --fixed-strings "$HOME" "$TARGET"; then
    die "The release still contains the builder's home path."
fi
if rg -a -i -q 'brodie\.owens@|@outlook\.com' "$TARGET"; then
    die "Potential account data found in the release."
fi

RUNNER_ASSET="$DIST/ascension-winecx26-rosettax87-mingw-v$VERSION.tar.xz"
PACKAGE_ASSET="$DIST/ascension-macos-heroic-v$VERSION.tar.gz"
SOURCE_ASSET="$DIST/crossover-sources-26.0.0.tar.gz"
rm -f "$RUNNER_ASSET" "$PACKAGE_ASSET" "$SOURCE_ASSET" "$DIST/SHA256SUMS"

/usr/bin/tar -cJf "$RUNNER_ASSET" -C "$STAGE" "$NAME"
/usr/bin/tar -czf "$PACKAGE_ASSET" \
    --exclude='.git' --exclude='dist' -C "$(dirname "$ROOT")" "$(basename "$ROOT")"
cp -p "$SOURCE_ARCHIVE" "$SOURCE_ASSET"

(cd "$DIST" && shasum -a 256 "$(basename "$RUNNER_ASSET")" \
    "$(basename "$PACKAGE_ASSET")" "$(basename "$SOURCE_ASSET")" > SHA256SUMS)

printf 'Release assets created in %s\n' "$DIST"
ls -lh "$RUNNER_ASSET" "$PACKAGE_ASSET" "$SOURCE_ASSET" "$DIST/SHA256SUMS"
