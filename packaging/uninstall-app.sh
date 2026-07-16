#!/bin/bash
set -euo pipefail

MODE=""
APP=""
SUPPORT="$HOME/Library/Application Support/Project Ascension"
RUNNER="/Users/Shared/PAWine"
LOGS="$HOME/Library/Logs/Project Ascension"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE=${2:-}; shift 2 ;;
        --app) APP=${2:-}; shift 2 ;;
        *) exit 2 ;;
    esac
done

case "$MODE" in app|runtime|all) ;; *) exit 2 ;; esac
[[ -n "$APP" && "$APP" == *.app ]] || exit 2

mkdir -p "$LOGS"
LOG="$LOGS/uninstall.log"
exec >> "$LOG" 2>&1
printf '[%s] Uninstalling Project Ascension (%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE"

# Allow the settings helper and menu action to return before stopping Wine and
# removing the application that launched this detached script.
sleep 2
if [[ -x "$RUNNER/bin/wineserver" ]]; then
    WINEPREFIX="$SUPPORT/prefix" "$RUNNER/bin/wineserver" -k || true
fi
/usr/bin/pkill -f 'Ascension Launcher\.exe|ascension-live.*Ascension\.exe|MMgr64\.exe' || true
/usr/bin/pkill -f '/Project Ascension\.app/Contents/MacOS/Project Ascension' || true
sleep 1

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ ! -x "$LSREGISTER" ]] || "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true

rm -rf "$APP"
if [[ "$MODE" == runtime || "$MODE" == all ]]; then
    rm -rf "$RUNNER"
fi
if [[ "$MODE" == all ]]; then
    rm -rf "$SUPPORT"
fi

/usr/bin/osascript -e 'display notification "Project Ascension was removed." with title "Uninstall Complete"' || true
if [[ "$MODE" == all ]]; then
    rm -rf "$LOGS"
fi
