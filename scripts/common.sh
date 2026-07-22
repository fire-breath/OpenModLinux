#!/usr/bin/env bash
# Shared helpers for OpenModLinux scripts.

set -Eeuo pipefail
IFS=$'\n\t'

OML_VERSION="0.2.0"

oml_now() {
    date '+%Y-%m-%d %H:%M:%S'
}

oml_log() {
    local level="$1"
    shift
    local message="$*"
    printf '[%s] [%s] %s\n' "$(oml_now)" "$level" "$message" >&2
    if [[ -n "${OML_LOG_FILE:-}" ]]; then
        mkdir -p "$(dirname "$OML_LOG_FILE")"
        printf '[%s] [%s] %s\n' "$(oml_now)" "$level" "$message" >>"$OML_LOG_FILE"
    fi
}

oml_info() { oml_log INFO "$@"; }
oml_warn() { oml_log WARN "$@"; }
oml_error() { oml_log ERROR "$@"; }

oml_die() {
    oml_error "$*"
    exit 1
}

oml_require() {
    local name
    for name in "$@"; do
        command -v "$name" >/dev/null 2>&1 || oml_die "Required command not found: $name"
    done
}

oml_realpath() {
    if command -v realpath >/dev/null 2>&1; then
        realpath -m -- "$1"
    else
        python3 - "$1" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
    fi
}

oml_atomic_write() {
    local destination="$1"
    local mode="${2:-0644}"
    local parent temporary
    parent="$(dirname "$destination")"
    mkdir -p "$parent"
    temporary="$(mktemp "$parent/.openmodlinux.XXXXXX")"
    cat >"$temporary"
    chmod "$mode" "$temporary"
    mv -f -- "$temporary" "$destination"
}

oml_escape_env_value() {
    printf '%q' "$1"
}

oml_safe_link() {
    local source="$1"
    local target="$2"
    local parent
    parent="$(dirname "$target")"
    mkdir -p "$parent"

    if [[ -L "$target" ]]; then
        if [[ "$(readlink -f -- "$target" 2>/dev/null || true)" == "$(readlink -f -- "$source" 2>/dev/null || true)" ]]; then
            return 0
        fi
        rm -f -- "$target"
    elif [[ -e "$target" ]]; then
        oml_warn "Not replacing existing non-symlink path: $target"
        return 1
    fi

    ln -s -- "$source" "$target"
}

# BEGIN OPENMODLINUX UNIFIED PREFIX HELPERS
oml_prefix_drive_c() {
    local prefix="$1"

    if [[ -d "$prefix/drive_c" ]]; then
        printf '%s\n' "$prefix/drive_c"
        return 0
    fi

    if [[ -d "$prefix/pfx/drive_c" ]]; then
        printf '%s\n' "$prefix/pfx/drive_c"
        return 0
    fi

    return 1
}

oml_prepare_prefix_compat() {
    local prefix="$1"

    if [[ -d "$prefix/pfx/drive_c" && ! -e "$prefix/drive_c" ]]; then
        ln -s "pfx/drive_c" "$prefix/drive_c"
        if declare -F oml_info >/dev/null 2>&1; then
            oml_info "Created UMU compatibility link: $prefix/drive_c -> pfx/drive_c"
        else
            printf 'Created UMU compatibility link: %s/drive_c -> pfx/drive_c\n' "$prefix"
        fi
    fi

    [[ -d "$prefix/drive_c" || -d "$prefix/pfx/drive_c" ]]
}

oml_find_vortex_executable() {
    local prefix="$1"
    local drive_c
    drive_c="$(oml_prefix_drive_c "$prefix")" || return 1

    local canonical="$drive_c/Program Files/Vortex/Vortex.exe"
    if [[ -f "$canonical" ]]; then
        printf '%s\n' "$canonical"
        return 0
    fi

    find "$drive_c/Program Files" "$drive_c/Program Files (x86)" \
        -type f -iname 'Vortex.exe' -print -quit 2>/dev/null
}
# END OPENMODLINUX UNIFIED PREFIX HELPERS
