#!/usr/bin/env bash
set -u
IFS=$'\n\t'

APPID="${APPID:-489830}"
GAME="${GAME:-$HOME/.local/share/Steam/steamapps/common/Skyrim Special Edition}"
COMPAT="${COMPAT:-$HOME/.local/share/Steam/steamapps/compatdata/$APPID}"
PREFIX="${PREFIX:-$COMPAT/pfx}"
PLUGIN="${PLUGIN:-${1:-}}"
PLUGINS="$GAME/Data/SKSE/Plugins"

[[ -n "$PLUGIN" ]] || {
    echo "Usage: $0 PLUGIN_BASENAME" >&2
    echo "Example: $0 IsekaiHeroSKSE" >&2
    exit 2
}
PLUGIN="${PLUGIN%.dll}"

TS="$(date +%Y%m%d_%H%M%S)"
SAFE_PLUGIN="$(printf '%s' "$PLUGIN" | tr -c 'A-Za-z0-9._-' '_')"
OUT="$HOME/SKSE_${SAFE_PLUGIN}_debug_$TS"
REPORT="$OUT/report.txt"
ARCHIVE_OUT="$HOME/SKSE_${SAFE_PLUGIN}_debug_$TS.tar.gz"

mkdir -p "$OUT"
exec > >(tee -a "$REPORT") 2>&1

finish() {
    local rc=$?
    trap - EXIT
    echo
    echo "============================================================"
    echo "Diagnostic return code: $rc"
    echo "Report: $REPORT"
    tar -czf "$ARCHIVE_OUT" -C "$OUT" . 2>/dev/null || true
    echo "Archive: $ARCHIVE_OUT"
    if [[ -t 0 ]]; then
        read -r -p "Press Enter to close..." _
    fi
    exit "$rc"
}
trap finish EXIT

section() {
    echo
    echo "################################################################"
    echo "# $*"
    echo "################################################################"
}

section "ENVIRONMENT"
date
echo "APPID=$APPID"
echo "GAME=$GAME"
echo "PREFIX=$PREFIX"
echo "PLUGIN=$PLUGIN"
uname -a

[[ -d "$GAME" ]] || {
    echo "ERROR: game directory not found: $GAME"
    exit 1
}

section "GAME AND SKSE"
for file in "$GAME/SkyrimSE.exe" "$GAME/skse64_loader.exe"; do
    if [[ -f "$file" ]]; then
        file "$file" 2>/dev/null || true
        stat -c 'size=%s modified=%y file=%n' "$file" 2>/dev/null || true
        sha256sum "$file" 2>/dev/null || true
    else
        echo "MISSING: $file"
    fi
done

find "$GAME" -maxdepth 1 -type f -iname 'skse64_*.dll' \
    -printf '%s bytes %TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort || true

section "PLUGIN FILES"
DLL="$PLUGINS/$PLUGIN.dll"
PDB="$PLUGINS/$PLUGIN.pdb"
for file in "$DLL" "$PDB"; do
    if [[ -f "$file" ]]; then
        file "$file" 2>/dev/null || true
        stat -c 'size=%s modified=%y file=%n' "$file" 2>/dev/null || true
        sha256sum "$file" 2>/dev/null || true
    else
        echo "MISSING: $file"
    fi
done

if [[ -f "$PDB" ]] && command -v llvm-pdbutil >/dev/null 2>&1; then
    llvm-pdbutil dump -summary "$PDB" 2>&1 | head -160 || true
fi

section "DLL IMPORTS"
IMPORTS="$OUT/imports.txt"
: >"$IMPORTS"
if [[ -f "$DLL" ]] && command -v objdump >/dev/null 2>&1; then
    objdump -p "$DLL" 2>/dev/null |
        sed -n 's/^[[:space:]]*DLL Name: //p' |
        sort -fu | tee "$IMPORTS"
fi

while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    case "${dep,,}" in
        api-ms-win-*|ext-ms-win-*) echo "API-SET: $dep"; continue ;;
    esac

    found=""
    for candidate in \
        "$GAME/$dep" \
        "$PLUGINS/$dep" \
        "$PREFIX/drive_c/windows/system32/$dep" \
        "$PREFIX/drive_c/windows/syswow64/$dep"
    do
        if [[ -f "$candidate" ]]; then
            found="$candidate"
            break
        fi
    done

    if [[ -n "$found" ]]; then
        echo "FOUND: $dep -> $found"
        file "$found" 2>/dev/null || true
    else
        echo "NOT FOUND AS FILE: $dep"
    fi
done <"$IMPORTS"

section "ADDRESS LIBRARY"
find "$PLUGINS" -maxdepth 1 -type f \
    \( -iname 'version*.bin' -o -iname 'versionlib*.bin' \) \
    -printf '%s bytes %TY-%Tm-%Td %TH:%TM %f\n' 2>/dev/null |
    sort || true

section "PLUGIN LISTS"
find "$PREFIX/drive_c/users" "$HOME/.local/share/Steam/userdata" \
    -type f \( -iname plugins.txt -o -iname loadorder.txt \) \
    -print 2>/dev/null |
while IFS= read -r list; do
    echo "--- $list"
    grep -iE "${PLUGIN}|${PLUGIN%SKSE}" "$list" 2>/dev/null || true
done

section "RECENT LOGS"
LOG_ROOTS=(
    "$HOME/Документы/My Games/Skyrim Special Edition"
    "$HOME/Documents/My Games/Skyrim Special Edition"
    "$PREFIX/drive_c/users/steamuser/Documents/My Games/Skyrim Special Edition"
    "$PREFIX/drive_c/users/steamuser/My Documents/My Games/Skyrim Special Edition"
)

for root in "${LOG_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' log; do
        echo
        echo "================================================================"
        echo "$log"
        echo "================================================================"
        tail -400 "$log" 2>/dev/null || true
        cp -a "$log" "$OUT/$(printf '%s' "$log" | sed 's#[/ ]#_#g')" 2>/dev/null || true
    done < <(
        find "$root" -maxdepth 6 -type f \
            \( -iname "$PLUGIN.log" \
               -o -iname skse64.log \
               -o -iname skse64_loader.log \
               -o -iname 'crash-*.log' \
               -o -iname 'crash-*.txt' \
               -o -iname '*CrashLogger*.log' \
               -o -iname EngineFixes.log \) \
            -mmin -1440 -print0 2>/dev/null
    )
done

section "PROTON LOG"
PROTON_LOG="$HOME/steam-$APPID.log"
if [[ -f "$PROTON_LOG" ]]; then
    grep -iE "$PLUGIN|exception|access_violation|c0000005|msvcp|vcruntime|d3dcompiler" \
        "$PROTON_LOG" 2>/dev/null | tail -600 || true
    cp -a "$PROTON_LOG" "$OUT/" 2>/dev/null || true
else
    echo "No Proton log: $PROTON_LOG"
    echo "Temporarily prepend PROTON_LOG=1 to Steam launch options."
fi

section "COREDUMPS"
coredumpctl --no-pager list --since "-2 hours" 2>/dev/null |
    grep -iE 'Skyrim|skse|wine|proton' | tail -80 || true
