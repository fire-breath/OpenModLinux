#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-normal}"

BASE='WINEDLLOVERRIDES="d3dx9_42=n,b;msvcp140=n,b;vcruntime140=n,b;vcruntime140_1=n,b" bash -c '\''args=("${@/SkyrimSELauncher.exe/skse64_loader.exe}"); args=("${args[@]/SkyrimSE.exe/skse64_loader.exe}"); exec "${args[@]}"'\'' -- %command%'

case "$MODE" in
    normal)
        printf '%s\n' "$BASE"
        ;;
    debug)
        printf 'PROTON_LOG=1 %s\n' "$BASE"
        ;;
    minimal)
        printf '%s\n' 'bash -c '\''args=("${@/SkyrimSELauncher.exe/skse64_loader.exe}"); args=("${args[@]/SkyrimSE.exe/skse64_loader.exe}"); exec "${args[@]}"'\'' -- %command%'
        ;;
    *)
        printf 'Usage: %s [normal|debug|minimal]\n' "$0" >&2
        exit 2
        ;;
esac
