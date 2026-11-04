#!/usr/bin/env bash
# Runtime handler for nxm:// links.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
STATE_FILE="$SCRIPT_DIR/state.env"

[[ -r "$STATE_FILE" ]] || {
    printf 'OpenModLinux state file is missing: %s\n' "$STATE_FILE" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$STATE_FILE"

URL="${1:-}"
case "$URL" in
    nxm://*|nxm-protocol://*) ;;
    *)
        printf 'Refusing unsupported URL: %s\n' "$URL" >&2
        exit 2
        ;;
esac

[[ -d "${VORTEX_PREFIX:-}" ]] || {
    printf 'Vortex prefix is unavailable: %s\n' "${VORTEX_PREFIX:-}" >&2
    exit 3
}
[[ -x "${WINE_BINARY:-}" ]] || {
    printf 'Configured Wine binary is unavailable: %s\n' "${WINE_BINARY:-}" >&2
    exit 4
}
[[ -f "${VORTEX_EXECUTABLE:-}" ]] || {
    printf 'Vortex executable is unavailable: %s\n' "${VORTEX_EXECUTABLE:-}" >&2
    exit 5
}

# find acitve proton
ACTIVE_SERVER="$(pgrep -a wineserver 2>/dev/null | grep -v ' -w' | grep -o '/.*wineserver' | head -n 1 || true)"
if [[ -n "$ACTIVE_SERVER" ]]; then
    if [[ "$ACTIVE_SERVER" =~ (.*/compatibilitytools\.d/[^/]+) ]]; then
        export PROTONPATH="${BASH_REMATCH[1]}"
    fi
fi

if [[ -z "${PROTONPATH:-}" ]]; then
    LUTRIS_YML="$(ls "$HOME/.local/share/lutris/games/"*vortex*.yml 2>/dev/null | head -n 1 || true)"
    if [[ -f "$LUTRIS_YML" ]]; then
        LUTRIS_VER="$(grep -E '^\s*version:' "$LUTRIS_YML" | head -n 1 | awk '{print $2}' | tr -d '"'\''')"
        if [[ -n "$LUTRIS_VER" && -d "$HOME/.local/share/Steam/compatibilitytools.d/$LUTRIS_VER" ]]; then
            export PROTONPATH="$HOME/.local/share/Steam/compatibilitytools.d/$LUTRIS_VER"
        fi
    fi
fi

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
{
    printf '[%s] URL received: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$URL"
    if [[ -n "${PROTONPATH:-}" ]]; then
        printf '[%s] Using Proton path: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$PROTONPATH"
    fi

    env \
        WINEPREFIX="$VORTEX_PREFIX" \
        WINEDEBUG=-all \
        ${PROTONPATH:+PROTONPATH="$PROTONPATH"} \
        "$WINE_BINARY" "$VORTEX_EXECUTABLE" -d "$URL"
} >>"$LOG_DIR/nxm-handler.log" 2>&1 &
disown || true