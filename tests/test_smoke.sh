#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_file() { [[ -f "$1" ]] || fail "file missing: $1"; }
assert_dir() { [[ -d "$1" ]] || fail "directory missing: $1"; }
assert_link() { [[ -L "$1" ]] || fail "symlink missing: $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"; }

printf '1. Checking Bash syntax...\n'
for file in "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh; do
    bash -n "$file"
done

printf '2. Checking Python syntax...\n'
python3 -m py_compile "$ROOT/scripts/steam-libraries.py"

printf '3. Creating fake Steam installation...\n'
HOME_DIR="$TMP/home"
STEAM_ROOT="$HOME_DIR/.local/share/Steam"
LIBRARY_TWO="$TMP/Games/SteamLibrary"
mkdir -p "$STEAM_ROOT/steamapps/common/Test Game One"
mkdir -p "$LIBRARY_TWO/steamapps/common/Test Game Two"

cat >"$STEAM_ROOT/steamapps/libraryfolders.vdf" <<EOF_VDF
"libraryfolders"
{
    "0"
    {
        "path" "$STEAM_ROOT"
    }
    "1"
    {
        "path" "$LIBRARY_TWO"
    }
}
EOF_VDF

cat >"$STEAM_ROOT/steamapps/appmanifest_100.acf" <<'EOF_ACF'
"AppState"
{
    "appid" "100"
    "name" "Test Game One"
    "installdir" "Test Game One"
}
EOF_ACF

cat >"$LIBRARY_TWO/steamapps/appmanifest_200.acf" <<'EOF_ACF'
"AppState"
{
    "appid" "200"
    "name" "Test Game Two"
    "installdir" "Test Game Two"
}
EOF_ACF

printf '4. Testing Steam discovery...\n'
DISCOVERY="$TMP/discovery.json"
HOME="$HOME_DIR" python3 "$ROOT/scripts/steam-libraries.py" --pretty >"$DISCOVERY"
python3 - "$DISCOVERY" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
assert len(data["libraries"]) == 2, data
assert {app["appid"] for app in data["apps"]} == {"100", "200"}, data
PY

printf '5. Testing synthetic Steam tree generation...\n'
PREFIX="$TMP/prefix with spaces"
mkdir -p "$PREFIX/drive_c"
HOME="$HOME_DIR" "$ROOT/scripts/sync-steam.sh" "$PREFIX" >"$TMP/sync.out"
SYNTHETIC="$PREFIX/drive_c/Program Files (x86)/Steam/steamapps"
assert_dir "$SYNTHETIC/common"
assert_link "$SYNTHETIC/common/Test Game One"
assert_link "$SYNTHETIC/common/Test Game Two"
assert_link "$SYNTHETIC/appmanifest_100.acf"
assert_link "$SYNTHETIC/appmanifest_200.acf"
assert_file "$SYNTHETIC/libraryfolders.vdf"
assert_contains "$SYNTHETIC/libraryfolders.vdf" 'OpenModLinux synthetic library'

printf '6. Testing NXM desktop handler generation...\n'
OML_DIR="$PREFIX/openmodlinux"
mkdir -p "$OML_DIR"
cp "$ROOT/scripts/common.sh" "$OML_DIR/common.sh"
cp "$ROOT/scripts/nxm-handler.sh" "$OML_DIR/nxm-handler.sh"
chmod +x "$OML_DIR"/*.sh
VORTEX_EXE="$PREFIX/drive_c/Program Files/Black Tree Gaming Ltd/Vortex/Vortex.exe"
mkdir -p "$(dirname "$VORTEX_EXE")"
: >"$VORTEX_EXE"
FAKE_WINE="$TMP/bin/wine runner"
mkdir -p "$(dirname "$FAKE_WINE")"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FAKE_WINE"
chmod +x "$FAKE_WINE"
mkdir -p "$TMP/mockbin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/mockbin/xdg-mime"
printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/mockbin/update-desktop-database"
chmod +x "$TMP/mockbin"/*

HOME="$HOME_DIR" PATH="$TMP/mockbin:$PATH" \
    "$ROOT/scripts/install-nxm-handler.sh" "$PREFIX" "$FAKE_WINE"
DESKTOP="$HOME_DIR/.local/share/applications/openmodlinux-vortex-nxm.desktop"
assert_file "$DESKTOP"
assert_file "$OML_DIR/state.env"
assert_contains "$DESKTOP" 'x-scheme-handler/nxm'
assert_contains "$DESKTOP" 'Exec="'

printf '7. Checking local YAML structure...\n'
python3 - "$ROOT/lutris/vortex.yml" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("PyYAML unavailable; structural YAML check skipped")
    raise SystemExit(0)
with open(sys.argv[1], encoding="utf-8") as stream:
    data = yaml.safe_load(stream)
assert data["runner"] == "wine"
script = data["script"]
assert script["game"]["arch"] == "win64"
assert any("wineexec" == task.get("task", {}).get("name") for task in script["installer"])
PY

printf 'Testing Skyrim/Vortex Linux tools...\n'
"$ROOT/tests/test_skyrim_tools.sh"
printf 'PASS: all smoke tests completed successfully.\n'
