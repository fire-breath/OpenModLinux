#!/usr/bin/env bash
# Register the OpenModLinux NXM handler in the current desktop session.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

PREFIX="${1:-${VORTEX_PREFIX:-}}"
WINE_BINARY="${2:-${WINE_BINARY:-}}"
[[ -n "$PREFIX" && -n "$WINE_BINARY" ]] || oml_die "Usage: $0 PREFIX WINE_BINARY"

PREFIX="$(oml_realpath "$PREFIX")"
WINE_BINARY="$(oml_realpath "$WINE_BINARY")"
OML_DIR="$PREFIX/openmodlinux"
VORTEX_EXECUTABLE="${VORTEX_EXECUTABLE_OVERRIDE:-}"
if [[ -z "$VORTEX_EXECUTABLE" ]]; then
    oml_prepare_prefix_compat "$PREFIX" || oml_die "Invalid Wine/UMU prefix: $PREFIX"
    VORTEX_EXECUTABLE="$(oml_find_vortex_executable "$PREFIX" || true)"
fi
[[ -n "$VORTEX_EXECUTABLE" && -f "$VORTEX_EXECUTABLE" ]] || \
    oml_die "Vortex executable was not found in prefix: $PREFIX"

APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_FILE="$APPLICATIONS_DIR/openmodlinux-vortex-nxm.desktop"
HANDLER="$OML_DIR/nxm-handler.sh"
STATE_FILE="$OML_DIR/state.env"
OML_LOG_FILE="$OML_DIR/logs/install-nxm-handler.log"

oml_require xdg-mime mkdir chmod
[[ -x "$HANDLER" ]] || oml_die "NXM handler is missing or not executable: $HANDLER"

{
    printf 'VORTEX_PREFIX=%s\n' "$(oml_escape_env_value "$PREFIX")"
    printf 'WINE_BINARY=%s\n' "$(oml_escape_env_value "$WINE_BINARY")"
    printf 'VORTEX_EXECUTABLE=%s\n' "$(oml_escape_env_value "$VORTEX_EXECUTABLE")"
} | oml_atomic_write "$STATE_FILE" 0600

mkdir -p "$APPLICATIONS_DIR"
desktop_exec="${HANDLER//\\/\\\\}"
desktop_exec="${desktop_exec//\"/\\\"}"

cat <<EOF_DESKTOP | oml_atomic_write "$DESKTOP_FILE" 0644
[Desktop Entry]
Type=Application
Name=Vortex NXM Handler (OpenModLinux)
Comment=Open Nexus Mods download links in Vortex installed by Lutris
Exec="$desktop_exec" %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/nxm;x-scheme-handler/nxm-protocol;
Categories=Game;
EOF_DESKTOP

xdg-mime default "$(basename "$DESKTOP_FILE")" x-scheme-handler/nxm
xdg-mime default "$(basename "$DESKTOP_FILE")" x-scheme-handler/nxm-protocol
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi

oml_info "Registered NXM handler: $DESKTOP_FILE"
