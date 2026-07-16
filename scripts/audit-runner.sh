#!/bin/bash
set -euo pipefail

ROOT=${1:-}
SOURCE_ARCHIVE=${2:-}

die() { printf 'Runner audit failed: %s\n' "$*" >&2; exit 1; }

[[ -d "$ROOT" ]] || die "runner directory not found: ${ROOT:-<missing>}"
for path in bin/wine bin/wineserver lib/wine share/wine; do
    [[ -e "$ROOT/$path" ]] || die "expected Wine path is missing: $path"
done

for entry in "$ROOT"/*; do
    case $(basename "$entry") in
        bin|lib|share|support|licenses) ;;
        *) die "unexpected top-level runner entry: $(basename "$entry")" ;;
    esac
done

allowed_bin='^(cx-alt-loader[.]py|function_grep[.]pl|widl|wine|wine-heroic|winebuild|winecpp|winedump|wineg[+][+]|winegcc|winemaker|wineserver|wmc|wrc)$'
while IFS= read -r entry; do
    name=$(basename "$entry")
    [[ "$name" =~ $allowed_bin ]] || die "unexpected executable in bin/: $name"
done < <(find "$ROOT/bin" -mindepth 1 -maxdepth 1 -print)

allowed_library='^lib(MacportsLegacySupport|MacportsLegacySystem[.]B|MoltenVK|SDL2|brotli|bz2|charset|exslt|ffi|freetype|gmp|gnutls|hogweed|iconv|icu|idn2|inotify|intl|lz4|lzma|nettle|p11-kit|pcap|png|tasn1|unistring|xml2|xslt|z|zstd)'
while IFS= read -r entry; do
    name=$(basename "$entry")
    if [[ -d "$entry" && "$name" == wine ]]; then
        continue
    fi
    if [[ "$name" == p11-kit-proxy.dylib ]]; then
        continue
    fi
    [[ "$name" =~ $allowed_library && "$name" == *.dylib ]] || \
        die "unexpected top-level runtime library: $name"
done < <(find "$ROOT/lib" -mindepth 1 -maxdepth 1 -print)

if [[ -d "$ROOT/support" ]]; then
    while IFS= read -r entry; do
        [[ $(basename "$entry") == ascension-runtime ]] || \
            die "unexpected support component: $(basename "$entry")"
    done < <(find "$ROOT/support" -mindepth 1 -maxdepth 1 -print)
fi

forbidden=$(find "$ROOT" -print | rg -i \
    '(^|/)(CrossOver[.]app|cxoffice|license[.]sig|cxsetup|cxinstaller|cxmenu|cxregister|cxupdate)(/|$)' || true)
[[ -z "$forbidden" ]] || die "proprietary CrossOver product artifact found: $forbidden"

if [[ -n "$SOURCE_ARCHIVE" ]]; then
    [[ -f "$SOURCE_ARCHIVE" ]] || die "source archive not found: $SOURCE_ARCHIVE"
    for path in sources/wine/COPYING.LIB sources/wine/LICENSE sources/moltenvk/LICENSE; do
        tar -tf "$SOURCE_ARCHIVE" | awk -v target="$path" \
            '$0 == target { found = 1 } END { exit found ? 0 : 1 }' || \
            die "source archive is missing required FOSS license: $path"
    done
    if tar -tf "$SOURCE_ARCHIVE" | awk \
        'tolower($0) ~ /(^|\/)(crossover[.]app|cxoffice|license[.]sig)(\/|$)/ { found = 1 } END { exit found ? 0 : 1 }'; then
        die "source archive contains a proprietary CrossOver product artifact"
    fi

    allowed_source='^(android|busybox|cabextract|dxvk|freetype|ghostscript|glib|gnutls|gstreamer|htmltextview|makedep|moltenvk|po4a|pyxdg|vkd3d|wine)$'
    while IFS= read -r package; do
        [[ "$package" =~ $allowed_source ]] || \
            die "unexpected package in CodeWeavers FOSS source archive: $package"
    done < <(tar -tf "$SOURCE_ARCHIVE" | awk -F/ \
        '$1 == "sources" && $2 != "" { print $2 }' | sort -u)
fi

printf 'Runner audit passed: Wine/FOSS layout only; no proprietary CrossOver product artifacts found.\n'
