#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SOURCE_DIR/common.sh"

PREFIX="${1:-}"
WINE_BINARY="${2:-}"
[[ -n "$PREFIX" ]] || {
    echo "Usage: $0 PREFIX [WINE_BINARY]" >&2
    exit 2
}

PREFIX="$(realpath -m "$PREFIX")"
[[ -d "$PREFIX" ]] || {
    echo "Prefix root does not exist: $PREFIX" >&2
    exit 1
}

oml_prepare_prefix_compat "$PREFIX" || {
    echo "Neither a classic Wine prefix nor an UMU/Proton pfx directory was found: $PREFIX" >&2
    exit 1
}

DRIVE_C="$(oml_prefix_drive_c "$PREFIX")"
VORTEX_EXECUTABLE="$(oml_find_vortex_executable "$PREFIX" || true)"
[[ -n "$VORTEX_EXECUTABLE" && -f "$VORTEX_EXECUTABLE" ]] || {
    echo "Vortex.exe was not found below $DRIVE_C." >&2
    exit 1
}

TARGET_DIR="$PREFIX/openmodlinux"
mkdir -p "$TARGET_DIR/logs"

files=(
    common.sh
    steam-libraries.py
    sync-steam.sh
    nxm-handler.sh
    install-nxm-handler.sh
    diagnose.sh
    uninstall-integration.sh
    wine-prefix-integration.sh
)

for file in "${files[@]}"; do
    if [[ -f "$SOURCE_DIR/$file" ]]; then
        install -m 0755 "$SOURCE_DIR/$file" "$TARGET_DIR/$file"
    fi
done

cat >"$TARGET_DIR/update.sh" <<'EOF_UPDATE'
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$SCRIPT_DIR/state.env" ]]; then
    source "$SCRIPT_DIR/state.env"
fi

if [[ -x "$SCRIPT_DIR/sync-steam.sh" ]]; then
    "$SCRIPT_DIR/sync-steam.sh" "${VORTEX_PREFIX:-$(dirname "$SCRIPT_DIR")}"
fi

if [[ -x "$SCRIPT_DIR/wine-prefix-integration.sh" ]]; then
    "$SCRIPT_DIR/wine-prefix-integration.sh" \
        --install-global \
        --prefix "${VORTEX_PREFIX:-$(dirname "$SCRIPT_DIR")}"
fi

printf 'OpenModLinux integration updated successfully.\n'
EOF_UPDATE
chmod 0755 "$TARGET_DIR/update.sh"

if [[ -x "$TARGET_DIR/sync-steam.sh" ]]; then
    echo "Synchronizing Steam libraries"
    "$TARGET_DIR/sync-steam.sh" "$PREFIX"
fi

if [[ -n "$WINE_BINARY" && -x "$WINE_BINARY" ]]; then
    REG_FILE="$TARGET_DIR/steam-path.reg"
    cat >"$REG_FILE" <<'EOF_REG'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Valve\Steam]
"SteamPath"="C:\\Program Files (x86)\\Steam"
"SteamExe"="C:\\Program Files (x86)\\Steam\\Steam.exe"
EOF_REG

    WINEPREFIX="$PREFIX" WINEDEBUG=-all \
        "$WINE_BINARY" regedit /S "$REG_FILE" >/dev/null 2>&1 || \
        echo "Предупреждение: запись SteamPath через regedit не выполнена."
fi

if [[ -x "$TARGET_DIR/install-nxm-handler.sh" ]]; then
    echo "Installing NXM URL handler"
    VORTEX_EXECUTABLE_OVERRIDE="$VORTEX_EXECUTABLE" \
        "$TARGET_DIR/install-nxm-handler.sh" "$PREFIX" "$WINE_BINARY" || \
        echo "Предупреждение: установка NXM handler завершилась с ошибкой."
fi

if [[ -x "$TARGET_DIR/wine-prefix-integration.sh" ]]; then
    echo "Installing unified Wine/Proton/Vortex folder integration"
    "$TARGET_DIR/wine-prefix-integration.sh" \
        --install-global \
        --prefix "$PREFIX"
fi

cat >"$TARGET_DIR/state.env" <<EOF_STATE
VORTEX_PREFIX=$(printf '%q' "$PREFIX")
VORTEX_EXECUTABLE=$(printf '%q' "$VORTEX_EXECUTABLE")
WINE_BINARY=$(printf '%q' "$WINE_BINARY")
EOF_STATE

echo "OpenModLinux integration installed in: $TARGET_DIR"
echo "Vortex executable: $VORTEX_EXECUTABLE"

# BEGIN VORTEX USERDATA ON STEAM DEVICE
if [[ -x "$SOURCE_DIR/configure-vortex-userdata.sh" ]]; then
    "$SOURCE_DIR/configure-vortex-userdata.sh" "$PREFIX"
fi
# END VORTEX USERDATA ON STEAM DEVICE
