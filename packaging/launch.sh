#!/bin/bash
set -euo pipefail

APP_ROOT=$(cd "$(dirname "$0")/.." && pwd)
RESOURCES="$APP_ROOT/Resources"
BUNDLED_RUNNER="$RESOURCES/WineCX26-RosettaX87-Mingw"
RUNNER="/Users/Shared/PAWine"
RUNTIME_MARKER="2026-07-16-prefix-modules1"
WINE="$RUNNER/bin/wine-heroic"
WINESERVER="$RUNNER/bin/wineserver"
ROSETTA_LOADER="$RUNNER/support/ascension-runtime/rosettax87"
INSTALLER="$RESOURCES/ascension-setup.exe"
PATCH_ASSETS="$RESOURCES/runtime-patch"
WINDOW_CONTROLS="$RESOURCES/ascension-window-controls.exe"
WINDOW_HOOK="$RESOURCES/ascension-window-hook.dll"
SETTINGS_HELPER="$RESOURCES/ascension-settings"
PROGRESS_HELPER="$RESOURCES/ascension-progress"
MENU_LIBRARY="$RESOURCES/libascension-menu.dylib"
SUPPORT="$HOME/Library/Application Support/Project Ascension"
PREFIX="$SUPPORT/prefix"
LAUNCHER_DIR="$PREFIX/drive_c/Program Files/Ascension Launcher"
LAUNCHER="$LAUNCHER_DIR/Ascension Launcher.exe"
GAME_DIR="$LAUNCHER_DIR/resources/ascension-live"
PATCH_STASH="$SUPPORT/runtime-patch-live"
PRODUCT_ID="b427df0f-4132-42b8-9eec-b504a7a5e3ba"
LOG_DIR="$HOME/Library/Logs/Project Ascension"
LOG="$LOG_DIR/launcher.log"
LOCK="$SUPPORT/.launching"
PATCH_MANAGER_PID=""
WINDOW_CONTROLS_PID=""
PROGRESS_PID=""
PROGRESS_PIPE=""
PROGRESS_OPEN=0

mkdir -p "$SUPPORT" "$LOG_DIR"

show_error() {
    local message=$1
    /usr/bin/osascript - "$message" "$LOG" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
    display dialog (item 1 of argv) & return & return & "A diagnostic log is available at:" & return & (item 2 of argv) buttons {"OK"} default button "OK" with title "Project Ascension"
end run
APPLESCRIPT
}

fail() {
    printf 'Error: %s\n' "$*" >> "$LOG"
    show_error "$*"
    exit 1
}

if [[ $(uname -m) != arm64 ]]; then
    fail "Project Ascension for Mac currently supports Apple Silicon Macs only."
fi

[[ -x "$BUNDLED_RUNNER/bin/wine-heroic" ]] || \
    fail "The bundled compatibility runtime is incomplete. Reinstall Project Ascension from the DMG."
[[ -f "$INSTALLER" ]] || fail "The bundled Ascension Launcher installer is missing."
[[ -f "$PATCH_ASSETS/libDllLdr.dll" && -f "$PATCH_ASSETS/d3d9.dll" ]] || \
    fail "The bundled macOS game compatibility files are missing. Reinstall Project Ascension from the DMG."
[[ -f "$WINDOW_CONTROLS" && -f "$WINDOW_HOOK" ]] || \
    fail "The bundled window controls helper is missing. Reinstall Project Ascension from the DMG."
[[ -x "$SETTINGS_HELPER" && -x "$PROGRESS_HELPER" && -f "$MENU_LIBRARY" ]] || \
    fail "A bundled macOS helper is missing. Reinstall Project Ascension from the DMG."

progress_start() {
    PROGRESS_PIPE="$SUPPORT/.setup-progress.$$"
    rm -f "$PROGRESS_PIPE"
    mkfifo "$PROGRESS_PIPE"
    "$PROGRESS_HELPER" "$PROGRESS_PIPE" &
    PROGRESS_PID=$!
    exec 9>"$PROGRESS_PIPE"
    PROGRESS_OPEN=1
}

progress_update() {
    [[ $PROGRESS_OPEN -eq 1 ]] || return 0
    printf '%s\t%s\n' "$1" "$2" >&9 2>/dev/null || true
}

progress_stop() {
    if [[ $PROGRESS_OPEN -eq 1 ]]; then
        exec 9>&-
        PROGRESS_OPEN=0
    fi
    if [[ -n "$PROGRESS_PID" ]]; then
        kill "$PROGRESS_PID" 2>/dev/null || true
        wait "$PROGRESS_PID" 2>/dev/null || true
        PROGRESS_PID=""
    fi
    [[ -z "$PROGRESS_PIPE" ]] || rm -f "$PROGRESS_PIPE"
}

if ! mkdir "$LOCK" 2>/dev/null; then
    fail "Project Ascension is already starting. If it is not visible, wait a moment and try again."
fi

cleanup() {
    progress_stop
    if [[ -n "$WINDOW_CONTROLS_PID" ]]; then
        kill "$WINDOW_CONTROLS_PID" 2>/dev/null || true
        wait "$WINDOW_CONTROLS_PID" 2>/dev/null || true
    fi
    if [[ -n "$PATCH_MANAGER_PID" ]]; then
        kill "$PATCH_MANAGER_PID" 2>/dev/null || true
        wait "$PATCH_MANAGER_PID" 2>/dev/null || true
    fi
    rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT

ensure_runtime() {
    local marker="$RUNNER/.ascension-runtime-version"
    if [[ -f "$marker" && $(cat "$marker") == "$RUNTIME_MARKER" \
        && -f "$RUNNER/lib/wine/x86_64-windows/msxml3.dll" \
        && -f "$RUNNER/lib/wine/i386-windows/msxml3.dll" ]]; then
        return
    fi

    local stage="/Users/Shared/.PAWine.$UID.$$"
    rm -rf "$stage"
    if ! /usr/bin/ditto "$BUNDLED_RUNNER" "$stage"; then
        rm -rf "$stage"
        fail "The compatibility runtime could not be installed in /Users/Shared."
    fi
    printf '%s\n' "$RUNTIME_MARKER" > "$stage/.ascension-runtime-version"
    rm -rf "$RUNNER" 2>/dev/null || {
        rm -rf "$stage"
        fail "An incompatible shared runtime already exists at $RUNNER and could not be replaced."
    }
    mv "$stage" "$RUNNER"
}

apply_pending_maintenance() {
    if [[ -f "$SUPPORT/.repair-runtime" ]]; then
        printf 'Reinstalling the compatibility runtime by request.\n'
        rm -f "$SUPPORT/.repair-runtime"
        rm -rf "$RUNNER" || fail "The compatibility runtime could not be removed for repair."
    fi
}

FIRST_SETUP=0
if [[ ! -f "$SUPPORT/.prefix-ready" || ! -f "$LAUNCHER" \
    || ! -f "$PREFIX/drive_c/windows/system32/msvcp140.dll" \
    || ! -f "$PREFIX/drive_c/windows/syswow64/msvcp140.dll" ]]; then
    FIRST_SETUP=1
fi

if [[ $FIRST_SETUP -eq 1 ]]; then
    /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
display dialog "Project Ascension will now prepare its Windows compatibility environment. A progress window will show each setup stage." buttons {"Continue"} default button "Continue" with title "Project Ascension"
APPLESCRIPT
    progress_start
    progress_update 5 "Starting first-time setup…"
fi

progress_update 10 "Installing the compatibility runtime…"
apply_pending_maintenance
ensure_runtime
progress_update 20 "Compatibility runtime installed."

[[ -x "$WINE" && -x "$WINESERVER" && -x "$ROSETTA_LOADER" ]] || \
    fail "The installed compatibility runtime is incomplete."

wine_env() {
    env WINEPREFIX="$PREFIX" WINEMSYNC=1 \
        DXVK_ASYNC=1 \
        ROSETTA_X87_PATH="$ROSETTA_LOADER" \
        ROSETTA_X87_EXTENDED_FPR_SCRATCH=1 \
        WINEDLLOVERRIDES='d3d9=n,b' \
        WINEDEBUG=-all "$@"
}

installer_env() {
    env WINEPREFIX="$PREFIX" WINEMSYNC=1 \
        ROSETTA_X87_PATH="$ROSETTA_LOADER" \
        ROSETTA_X87_EXTENDED_FPR_SCRATCH=1 \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
        WINEDEBUG=-all "$@"
}

launcher_env() {
    local hud
    hud=$("$SETTINGS_HELPER" --print-hud)
    wine_env env \
        ASCENSION_MENU_ENABLED=1 \
        ASCENSION_APP_ROOT="$(dirname "$APP_ROOT")" \
        ASCENSION_APP_RESOURCES="$RESOURCES" \
        ASCENSION_DYLD_INSERT_LIBRARIES="$MENU_LIBRARY" \
        DXVK_HUD="$hud" \
        "$@"
}

patch_stash_ready() {
    [[ -f "$PATCH_STASH/.ready" \
        && -f "$PATCH_STASH/DivxDecoder.dll" \
        && -f "$PATCH_STASH/DivxDecoderOriginal.dll" \
        && -f "$PATCH_STASH/DivxTac.dll" \
        && -f "$PATCH_STASH/DivxTacOriginal.dll" ]]
}

adopt_existing_patch_stash() {
    patch_stash_ready && return 0
    [[ -f "$PATCH_STASH/DivxDecoder.dll" \
        && -f "$PATCH_STASH/DivxDecoderOriginal.dll" \
        && -f "$PATCH_STASH/DivxTac.dll" \
        && -f "$PATCH_STASH/DivxTacOriginal.dll" ]] || return 0
    touch "$PATCH_STASH/.ready"
}

prepare_clean_game() {
    adopt_existing_patch_stash
    [[ -d "$GAME_DIR" ]] || return 0

    if patch_stash_ready; then
        cp -p "$PATCH_STASH/DivxDecoderOriginal.dll" "$GAME_DIR/DivxDecoder.dll"
        cp -p "$PATCH_STASH/DivxTacOriginal.dll" "$GAME_DIR/DivxTac.dll"
    fi

    rm -f "$GAME_DIR/DivxDecoder.dll.bak" \
        "$GAME_DIR/DivxDecoderOriginal.dll" \
        "$GAME_DIR/DivxTac.dll.bak" \
        "$GAME_DIR/DivxTacOriginal.dll" \
        "$GAME_DIR/d3d9.dll" \
        "$GAME_DIR/libDllLdr.dll" \
        "$GAME_DIR/winerosetta.dll" \
        "$GAME_DIR/libSiliconPatch.dll" \
        "$GAME_DIR/mods/winerosetta.dll" \
        "$GAME_DIR/mods/libSiliconPatch.dll" \
        "$GAME_DIR/rosettax87/rosettax87" \
        "$GAME_DIR/rosettax87/libRuntimeRosettax87"
    rmdir "$GAME_DIR/mods" "$GAME_DIR/rosettax87" 2>/dev/null || true
}

current_sidecar_url() {
    local url_file
    url_file=$(find "$PREFIX/drive_c/users" -type f \
        -path '*/AppData/Local/Temp/ascension-services-*.json' \
        -exec ls -t {} + 2>/dev/null | sed -n '1p')
    [[ -n "$url_file" ]] || return 1
    sed -E -n 's/.*"api_base_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        "$url_file" | sed -n '1p'
}

patch_state() {
    local api
    api=$(current_sidecar_url) || return 1
    [[ -n "$api" ]] || return 1
    /usr/bin/curl --silent --show-error --max-time 1 \
        "$api/v1/patch/$PRODUCT_ID/state" 2>/dev/null
}

build_patch_stash() {
    [[ -f "$GAME_DIR/DivxDecoder.dll" && -f "$GAME_DIR/DivxTac.dll" ]] || return 1

    local stage="/tmp/ascension-patch-$UID-$$"
    local next="$PATCH_STASH.next"
    rm -rf "$stage" "$next"
    mkdir -p "$stage" "$next/mods" "$next/rosettax87"

    cp -p "$GAME_DIR/DivxDecoder.dll" "$stage/DivxDecoder.dll"
    cp -p "$GAME_DIR/DivxTac.dll" "$stage/DivxTac.dll"
    cp -p "$PATCH_ASSETS/libDllLdr.dll" "$stage/libDllLdr.dll"

    if ! (cd "$stage" && installer_env "$WINE" rundll32 \
        libDllLdr.dll,PatchDivxDecoder "$stage" && \
        installer_env "$WINE" rundll32 libDllLdr.dll,PatchDivxTac "$stage"); then
        printf 'macOS game patch generation failed; it will be retried.\n'
        rm -rf "$stage" "$next"
        return 1
    fi

    cp -p "$stage/DivxDecoder.dll" "$next/DivxDecoder.dll"
    cp -p "$stage/DivxDecoder.dll.bak" "$next/DivxDecoderOriginal.dll"
    cp -p "$stage/DivxTac.dll" "$next/DivxTac.dll"
    cp -p "$stage/DivxTac.dll.bak" "$next/DivxTacOriginal.dll"
    touch -r "$GAME_DIR/DivxDecoder.dll" \
        "$next/DivxDecoder.dll" "$next/DivxDecoderOriginal.dll"
    touch -r "$GAME_DIR/DivxTac.dll" \
        "$next/DivxTac.dll" "$next/DivxTacOriginal.dll"

    cp -p "$PATCH_ASSETS/d3d9.dll" "$next/d3d9.dll"
    cp -p "$PATCH_ASSETS/libDllLdr.dll" "$next/libDllLdr.dll"
    cp -p "$PATCH_ASSETS/mods/winerosetta.dll" "$next/mods/winerosetta.dll"
    cp -p "$PATCH_ASSETS/mods/libSiliconPatch.dll" "$next/mods/libSiliconPatch.dll"
    cp -p "$PATCH_ASSETS/rosettax87/rosettax87" "$next/rosettax87/rosettax87"
    cp -p "$PATCH_ASSETS/rosettax87/libRuntimeRosettax87" \
        "$next/rosettax87/libRuntimeRosettax87"
    printf 'mods/winerosetta.dll\nmods/libSiliconPatch.dll\n' > "$next/dlls.txt"
    touch "$next/.ready"

    rm -rf "$PATCH_STASH"
    mv "$next" "$PATCH_STASH"
    rm -rf "$stage"
    printf 'Generated macOS game compatibility patch.\n'
}

activate_patch() {
    patch_stash_ready || return 1
    mkdir -p "$GAME_DIR/mods" "$GAME_DIR/rosettax87"

    cp -p "$PATCH_STASH/DivxDecoder.dll" "$GAME_DIR/DivxDecoder.dll"
    cp -p "$PATCH_STASH/DivxTac.dll" "$GAME_DIR/DivxTac.dll"
    restore_patch_extras
}

restore_patch_extras() {
    patch_stash_ready || return 1
    mkdir -p "$GAME_DIR/mods" "$GAME_DIR/rosettax87"

    [[ -f "$GAME_DIR/DivxDecoderOriginal.dll" ]] || \
        cp -p "$PATCH_STASH/DivxDecoderOriginal.dll" "$GAME_DIR/DivxDecoderOriginal.dll"
    [[ -f "$GAME_DIR/DivxDecoder.dll.bak" ]] || \
        cp -p "$PATCH_STASH/DivxDecoderOriginal.dll" "$GAME_DIR/DivxDecoder.dll.bak"
    [[ -f "$GAME_DIR/DivxTacOriginal.dll" ]] || \
        cp -p "$PATCH_STASH/DivxTacOriginal.dll" "$GAME_DIR/DivxTacOriginal.dll"
    [[ -f "$GAME_DIR/DivxTac.dll.bak" ]] || \
        cp -p "$PATCH_STASH/DivxTacOriginal.dll" "$GAME_DIR/DivxTac.dll.bak"

    local file
    for file in d3d9.dll libDllLdr.dll dlls.txt; do
        [[ -f "$GAME_DIR/$file" ]] || cp -p "$PATCH_STASH/$file" "$GAME_DIR/$file"
    done
    for file in winerosetta.dll libSiliconPatch.dll; do
        [[ -f "$GAME_DIR/$file" ]] || cp -p "$PATCH_STASH/mods/$file" "$GAME_DIR/$file"
        [[ -f "$GAME_DIR/mods/$file" ]] || cp -p "$PATCH_STASH/mods/$file" "$GAME_DIR/mods/$file"
    done
    for file in rosettax87 libRuntimeRosettax87; do
        [[ -f "$GAME_DIR/rosettax87/$file" ]] || \
            cp -p "$PATCH_STASH/rosettax87/$file" "$GAME_DIR/rosettax87/$file"
    done
}

runtime_patch_manager() {
    local launcher_pid=$1
    local state current_hash patched_hash original_hash

    while kill -0 "$launcher_pid" 2>/dev/null; do
        if [[ ! -f "$GAME_DIR/DivxDecoder.dll" || ! -f "$GAME_DIR/DivxTac.dll" ]]; then
            sleep 1
            continue
        fi

        state=$(patch_state || true)
        if [[ "$state" != *'"state":"up_to_date"'* || "$state" == *'"game_running":true'* ]]; then
            sleep 1
            continue
        fi

        if patch_stash_ready; then
            current_hash=$(shasum -a 256 "$GAME_DIR/DivxDecoder.dll" | awk '{print $1}')
            patched_hash=$(shasum -a 256 "$PATCH_STASH/DivxDecoder.dll" | awk '{print $1}')
            original_hash=$(shasum -a 256 "$PATCH_STASH/DivxDecoderOriginal.dll" | awk '{print $1}')
            if [[ "$current_hash" != "$patched_hash" && "$current_hash" != "$original_hash" ]]; then
                rm -rf "$PATCH_STASH"
            fi
        fi

        patch_stash_ready || build_patch_stash || {
            sleep 2
            continue
        }
        activate_patch
        break
    done

    while kill -0 "$launcher_pid" 2>/dev/null; do
        restore_patch_extras || true
        sleep 0.02
    done
}

ensure_prefix() {
    local system32="$PREFIX/drive_c/windows/system32"
    local syswow64="$PREFIX/drive_c/windows/syswow64"
    local source target
    mkdir -p "$system32" "$syswow64" "$PREFIX/dosdevices"
    [[ -e "$PREFIX/dosdevices/c:" || -L "$PREFIX/dosdevices/c:" ]] || \
        ln -s ../drive_c "$PREFIX/dosdevices/c:"
    [[ -e "$PREFIX/dosdevices/z:" || -L "$PREFIX/dosdevices/z:" ]] || \
        ln -s / "$PREFIX/dosdevices/z:"

    if [[ ! -f "$SUPPORT/.prefix-ready" ]]; then
        local boot_pid prefix_ready=0
        installer_env "$WINE" "$RUNNER/lib/wine/x86_64-windows/wineboot.exe" -u &
        boot_pid=$!
        for _ in {1..120}; do
            if [[ -d "$PREFIX/drive_c/users" && -f "$PREFIX/user.reg" ]]; then
                prefix_ready=1
                break
            fi
            sleep 1
        done
        if [[ -d "$PREFIX/drive_c/users" && -f "$PREFIX/user.reg" ]]; then
            prefix_ready=1
        fi
        if [[ $prefix_ready -eq 1 ]]; then
            # WineCX can wait indefinitely for its first-run desktop helper
            # after wine.inf has finished. The prefix is ready at this point;
            # stop the helper so installation can continue.
            WINEPREFIX="$PREFIX" "$WINESERVER" -k >/dev/null 2>&1 || true
            wait "$boot_pid" 2>/dev/null || true
        else
            WINEPREFIX="$PREFIX" "$WINESERVER" -k >/dev/null 2>&1 || true
            wait "$boot_pid" 2>/dev/null || true
            fail "The Windows compatibility environment could not be initialized."
        fi
        touch "$SUPPORT/.prefix-ready"
    fi

    # This PE build keeps Wine's Windows modules in the runtime rather than
    # copying hundreds of megabytes into each prefix. Link missing built-ins
    # only after wineboot has finished: its prefix cleanup can otherwise
    # remove the shared runtime files through these links.
    for source in "$RUNNER/lib/wine/x86_64-windows"/*; do
        target="$system32/$(basename "$source")"
        [[ -e "$target" || -L "$target" ]] || ln -s "$source" "$target"
    done
    for source in "$RUNNER/lib/wine/i386-windows"/*; do
        target="$syswow64/$(basename "$source")"
        [[ -e "$target" || -L "$target" ]] || ln -s "$source" "$target"
    done
}

configure_launcher() {
    local users_dir="$PREFIX/drive_c/users"
    local wine_user=""
    if [[ -d "$users_dir/crossover" ]]; then
        wine_user="$users_dir/crossover"
    else
        wine_user=$(find "$users_dir" -mindepth 1 -maxdepth 1 -type d \
            ! -iname 'Public' ! -iname 'Default*' ! -iname 'All Users' -print | sed -n '1p')
    fi
    [[ -n "$wine_user" ]] || return 0

    local config_dir="$wine_user/AppData/Local/ProjectAscension/Config"
    local config="$config_dir/AscensionLauncherSettings.json"
    mkdir -p "$config_dir"
    # The launcher tolerates this minimal settings document and adds its other
    # settings itself. Software rendering avoids the Electron black window.
    if [[ ! -f "$config" ]]; then
        printf '{\n  "enableHardwareAcceleration": false\n}\n' > "$config"
    elif ! grep -q '"enableHardwareAcceleration"[[:space:]]*:[[:space:]]*false' "$config"; then
        # Preserve unknown settings when possible. The launcher will repair a
        # missing key; only replace the known true value here.
        sed -E 's/("enableHardwareAcceleration"[[:space:]]*:[[:space:]]*)true/\1false/' \
            "$config" > "$config.tmp"
        mv "$config.tmp" "$config"
    fi
}

reset_launcher_data_if_requested() {
    [[ -f "$SUPPORT/.reset-launcher-data" ]] || return 0
    printf 'Resetting official launcher data by request.\n'
    local user_dir
    while IFS= read -r user_dir; do
        rm -rf "$user_dir/AppData/Roaming/projectascension" \
            "$user_dir/AppData/Local/projectascension-updater" \
            "$user_dir/AppData/Local/ProjectAscension/Config"
    done < <(find "$PREFIX/drive_c/users" -mindepth 1 -maxdepth 1 -type d \
        ! -iname 'Public' ! -iname 'Default*' ! -iname 'All Users' -print 2>/dev/null)
    rm -f "$SUPPORT/.reset-launcher-data"
}

install_vc_runtime() {
    local system32="$PREFIX/drive_c/windows/system32/msvcp140.dll"
    local syswow64="$PREFIX/drive_c/windows/syswow64/msvcp140.dll"
    if [[ -f "$system32" && ! -L "$system32" && -f "$syswow64" && ! -L "$syswow64" ]]; then
        return
    fi

    # Microsoft's WiX bootstrapper needs MSXML's COM classes. Register both
    # Wine architectures explicitly because wineboot does not always complete
    # that work before the first launcher run.
    local arch dll
    for arch in x86_64 i386; do
        for dll in msxml3.dll msxml6.dll; do
            installer_env "$WINE" "$RUNNER/lib/wine/$arch-windows/regsvr32.exe" /s \
                "$dll" || \
                fail "The Windows installer support components could not be registered."
        done
    done

    local downloads="$SUPPORT/downloads"
    local redist file part
    mkdir -p "$downloads"
    printf 'Installing Microsoft Visual C++ support files.\n'
    for arch in x86 x64; do
        file="$downloads/vc_redist.$arch.exe"
        if [[ ! -s "$file" ]]; then
            part="$file.part"
            rm -f "$part"
            /usr/bin/curl --fail --location --retry 3 \
                "https://aka.ms/vc14/vc_redist.$arch.exe" --output "$part" || {
                rm -f "$part"
                fail "Microsoft Visual C++ support files could not be downloaded. Check your internet connection and try again."
            }
            mv "$part" "$file"
        fi
        installer_env "$WINE" "$file" /install /quiet /norestart || \
            fail "Microsoft Visual C++ support files could not be installed."
    done

    [[ -f "$system32" && ! -L "$system32" && -f "$syswow64" && ! -L "$syswow64" ]] || \
        fail "Microsoft Visual C++ support files were installed but could not be verified."
}

{
    printf '\n[%s] Starting Project Ascension\n' "$(date '+%Y-%m-%d %H:%M:%S')"

    progress_update 25 "Preparing the Windows environment…"
    ensure_prefix
    progress_update 42 "Configuring launcher preferences…"

    reset_launcher_data_if_requested
    configure_launcher

    if [[ ! -f "$LAUNCHER" ]]; then
        progress_update 50 "Complete the official Ascension Launcher setup window."
        printf 'Opening the bundled official launcher installer.\n'
        installer_env "$WINE" "$INSTALLER"
        [[ -f "$LAUNCHER" ]] || fail "The Ascension Launcher was not installed. Open Project Ascension again to retry."
        # The NSIS installer can auto-start the launcher without our required
        # Electron flags. That hidden first instance then absorbs the supported
        # launch below through Electron's single-instance lock. Stop it after
        # setup and start one clean, correctly flagged instance ourselves.
        sleep 2
        WINEPREFIX="$PREFIX" "$WINESERVER" -k >/dev/null 2>&1 || true
        sleep 1
        configure_launcher
        progress_update 65 "Ascension Launcher installed."
    fi

    progress_update 70 "Installing Microsoft Windows components…"
    install_vc_runtime
    progress_update 85 "Microsoft Windows components installed."

    # Present pristine managed files during the launcher's initial verification
    # so its UI remains on Play. The manager activates the macOS patch only
    # after that check reports up-to-date, then restores support files if the
    # launcher's zero-byte preflight repair removes them before game startup.
    progress_update 90 "Preparing macOS game compatibility files…"
    prepare_clean_game

    # The Windows launcher disables SC_CLOSE, which Wine mirrors as a grey
    # macOS close control. Re-enable it from inside the launcher's process.
    window_control_args=()
    close_launcher=$("$SETTINGS_HELPER" --print-bool closeLauncherWhilePlaying)
    if [[ $close_launcher == 1 ]]; then
        window_control_args+=(--close-launcher-while-playing)
    elif [[ $("$SETTINGS_HELPER" --print-bool keepLauncherVisible) == 0 ]]; then
        window_control_args+=(--hide-launcher-while-playing)
    fi
    if [[ $close_launcher == 0 && $("$SETTINGS_HELPER" --print-bool showLauncherAfterGame) == 1 ]]; then
        window_control_args+=(--show-launcher-after-game)
    fi
    wine_env "$WINE" "$WINDOW_CONTROLS" "${window_control_args[@]}" &
    WINDOW_CONTROLS_PID=$!

    progress_update 100 "Setup complete. Opening Ascension Launcher…"
    /bin/sleep 0.4
    progress_stop
    printf 'Opening Ascension Launcher.\n'
    launcher_env "$WINE" "$LAUNCHER" \
        --no-sandbox --disable-gpu-sandbox --disable-gpu --use-angle=swiftshader &
    launcher_pid=$!
    runtime_patch_manager "$launcher_pid" &
    PATCH_MANAGER_PID=$!
    wait "$launcher_pid"
} >> "$LOG" 2>&1 || fail "Project Ascension could not be started."
