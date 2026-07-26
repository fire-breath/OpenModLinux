#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

TOOLS=(
    scripts/configure-vortex-native-steam.sh
    scripts/fix-vortex-glx.sh
    scripts/skyrim-skse-launch-options.sh
    scripts/install-engine-fixes-preloader.sh
    scripts/install-steam-vcrun.sh
    scripts/diagnose-skse-plugin.sh
    scripts/diagnose-isekai-hero.sh
)

for tool in "${TOOLS[@]}"; do
    [[ -f "$ROOT/$tool" ]] || {
        echo "Missing tool: $tool" >&2
        exit 1
    }
    bash -n "$ROOT/$tool"
done

normal="$("$ROOT/scripts/skyrim-skse-launch-options.sh" normal)"
debug="$("$ROOT/scripts/skyrim-skse-launch-options.sh" debug)"

grep -Fq 'skse64_loader.exe' <<<"$normal"
grep -Fq 'd3dx9_42=n,b' <<<"$normal"
grep -Fq 'vcruntime140_1=n,b' <<<"$normal"
grep -Fq 'PROTON_LOG=1' <<<"$debug"

grep -Fq 'C:\SteamLibrary' "$ROOT/scripts/configure-vortex-native-steam.sh"
grep -Fq 'vortex-userdata' "$ROOT/scripts/configure-vortex-native-steam.sh"
grep -Fq 'vc_redist.x64.exe' "$ROOT/scripts/install-steam-vcrun.sh"
grep -Fq 'IsekaiHeroSKSE' "$ROOT/scripts/diagnose-isekai-hero.sh"

echo "PASS: Skyrim/Vortex Linux tools"
