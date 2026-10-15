#!/usr/bin/env bash
# Builds FIFA Street (ReStreet) for linux-arm64 from your own FIFA Street
# (2012, Xbox 360) disc image, start to finish: the toolchain, the patched
# ReXGlue SDK, the game files from the ISO, the recompiled code, the game, and
# a ready folder to play from, added to Steam with its artwork. Made for the
# handheld itself (ArmadaOS on the Retroid Pocket 6, or any aarch64 Linux); it
# also runs on x86-64 Linux with qemu-user installed, and the result is then
# copied to the handheld. FS_ADD_TO_STEAM=0 leaves Steam alone.
#
#   scripts/build.sh ISO [DIR]
#
# ISO  your FIFA Street (Xbox 360) disc image, or - to use the game files an
#      earlier build extracted (to update)
# DIR  where everything goes (default ~/.local/share/FifaStreet-arm64);
#      about 30 GB free is needed while building
#
# Run it again after updating this repository: finished steps are skipped
# when nothing they depend on changed, and the game build recompiles only the
# files a change touches. The game is DIR/game (with its files in
# DIR/GameData); nothing made here may be published (it is built from your
# copy of the game).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 1 ] && { [ "$1" = - ] || [ -f "$1" ]; } || { echo "usage: $0 ISO|- [DIR]" >&2; exit 2; }
iso=-
[ "$1" = - ] || iso="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
dir="${2:-$HOME/.local/share/FifaStreet-arm64}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
tc="$dir/toolchain"
rs="$dir/ReStreet"
project="$rs/Installer/recomp-template"
sdk_src="$dir/rexglue-sdk"
sdk="$sdk_src/out/install/linux-arm64"
data="$dir/GameData"
game="$dir/game"
stamps="$dir/.stamps"
mkdir -p "$stamps"

step() { printf '\n==> %s\n' "$*"; }
key() { cat "$@" | sha256sum | cut -d' ' -f1; }  # key FILE...: a hash of their contents
done_with() { [ -f "$stamps/$1" ] && [ "$(cat "$stamps/$1")" = "$2" ]; }
mark() { echo "$2" > "$stamps/$1"; }

# aarch64 programs made here run natively on the handheld, under qemu elsewhere.
run=()
case "$(uname -m)" in
    aarch64|arm64) ;;
    x86_64|amd64)
        qemu="$(command -v qemu-aarch64-static || command -v qemu-aarch64 || true)"
        [ -n "$qemu" ] || { echo "error: on x86-64 this needs qemu-aarch64 (qemu-user)" >&2; exit 1; }
        run=("$qemu" -L "$tc/sysroot") ;;
    *) echo "error: build on aarch64 or x86-64 Linux" >&2; exit 1 ;;
esac

step "Toolchain"
"$repo/scripts/fetch-toolchain.sh" "$tc"
export PATH="$tc/bin:$PATH"

prepare_key="$(key "$repo/upstream.json" "$repo/scripts/prepare.sh" \
    "$repo"/patches/sdk/*.patch "$repo"/patches/game/*.patch)"
if done_with prepare "$prepare_key"; then
    echo "ReStreet and the SDK already prepared - skipping."
else
    step "ReStreet and the ReXGlue SDK"
    "$repo/scripts/prepare.sh" "$dir"
    mark prepare "$prepare_key"
fi

# The SDK, and the code recompiled with it, depend on the SDK patches, not on
# the game's.
sdk_key="$(key "$repo/upstream.json" "$repo/scripts/prepare.sh" "$repo"/patches/sdk/*.patch \
    "$repo/toolchain.json" "$repo/scripts/build-sdk.sh" "$repo/cmake/toolchains/linux-arm64.cmake")"
if done_with sdk "$sdk_key"; then
    echo "ReXGlue SDK already built - skipping."
else
    step "Building the ReXGlue SDK (this takes a while)"
    "$repo/scripts/build-sdk.sh" "$sdk_src" "$tc" "$sdk"
    mark sdk "$sdk_key"
fi

# The three recompiled modules: the game, its main DLL and the World Tour
# competition engine (in the disc's DLC folder).
main_xex="$data/default.xex"
dll_xex="$data/fifadllzf.xex.dll"
comp_xex="$data/dlc/dlc_FootballCompEng/dlc/FootballCompEng/FootballCompEngzf.xex.dll"

if [ -f "$main_xex" ] && { [ "$iso" = - ] || done_with extract "$iso"; }; then
    echo "Game files already extracted to $data - skipping."
elif [ "$iso" = - ]; then
    echo "error: no game files in $data yet: give your disc image instead of -" >&2
    exit 1
else
    step "Extracting the game from $iso"
    # Saints Reborn's XDVDFS extractor, downloaded at the commit and hash in
    # upstream.json and built here.
    tools="$dir/tools"
    mkdir -p "$tools"
    src="$tools/xiso_extract.cpp"
    url="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["xiso_extract"]["url"])' "$repo/upstream.json")"
    sum="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["xiso_extract"]["sha256"])' "$repo/upstream.json")"
    if [ ! -f "$src" ] || [ "$(sha256sum "$src" | cut -d' ' -f1)" != "$sum" ]; then
        curl -fsSL --retry 3 -o "$src.part" "$url"
        [ "$(sha256sum "$src.part" | cut -d' ' -f1)" = "$sum" ] ||
            { echo "error: $url does not match its hash in upstream.json" >&2; exit 1; }
        mv "$src.part" "$src"
    fi
    clang=("$tc/llvm/bin/clang++" --target=aarch64-linux-gnu "--sysroot=$tc/sysroot"
           -fuse-ld=lld -static-libstdc++)
    [ ! -e "$tc/bin/ld.lld" ] || clang+=("--ld-path=$tc/bin/ld.lld")
    "${clang[@]}" -std=c++17 -O2 -o "$tools/xiso_extract" "$src"
    rm -rf "$data"
    "${run[@]}" "$tools/xiso_extract" "$iso" "$data" \
        --skip-name '$SystemUpdate' --skip-name layer1filler.bin --skip-name layer2filler.bin
    [ -f "$main_xex" ] || {
        echo "error: the disc image has no default.xex - is it an Xbox 360 game disc?" >&2; exit 1; }
    mark extract "$iso"
fi
for f in "$dll_xex" "$comp_xex"; do
    [ -f "$f" ] || { echo "error: $f is missing: is this FIFA Street (2012) for Xbox 360?" >&2; exit 1; }
done

# The manifest, as ReStreet's own build writes it, with this machine's paths.
manifest="$project/fifastreet_manifest.toml"
cat > "$manifest.new" <<EOT
[project]
name = "fifastreet"
sdk_version = "0.10.0"
game_root = "$data"

[entrypoint]
file_path = "$main_xex"
out_directory_path = "generated/default"
includes = []

[[modules]]
guest_path = "game:\\\\fifadllzf.xex.dll"
file_path = "$dll_xex"
out_directory_path = "generated/fifadllzf_xex"
includes = ["config/fifadllzf_overrides.toml"]

[[modules]]
guest_path = "game:\\\\FootballCompEngzf.xex.dll"
file_path = "$comp_xex"
out_directory_path = "generated/FootballCompEngzf_xex"
includes = ["config/footballcompeng_overrides.toml"]
EOT
if cmp -s "$manifest.new" "$manifest"; then rm "$manifest.new"; else mv "$manifest.new" "$manifest"; fi

modules_key="$(key "$main_xex" "$dll_xex" "$comp_xex")"
codegen_key="$sdk_key $modules_key $(key "$manifest" "$project"/config/*.toml)"
if done_with codegen "$codegen_key" && [ -f "$project/generated/default/sources.cmake" ]; then
    echo "Recompiled code already generated - skipping."
else
    step "Recompiling the game's three modules (PowerPC to C++)"
    # Files that come out the same are left as they are (and not recompiled).
    (cd "$project" && LD_LIBRARY_PATH="$sdk/lib" "${run[@]}" "$sdk/bin/rexglue" \
        codegen fifastreet_manifest.toml --ignore-stamp)
    mark codegen "$codegen_key"
fi

step "Building FIFA Street (an hour or more on a handheld)"
"$repo/scripts/build-game.sh" "$project" "$sdk" "$tc" "$project/out/linux-arm64"

step "Copying the game to $game"
build="$project/out/linux-arm64"
mkdir -p "$game"
cp -f "$build/fifastreet" "$build"/libfifastreet_*_xex.so \
    "$sdk/lib/librexruntime.so" "$sdk/lib/librexgpu-xenos.so" "$game/"
install -m 755 "$repo/config/fifastreet.sh" "$game/fifastreet.sh"
# Your settings stay; the RP6 defaults go in only the first time.
[ -f "$game/fifastreet.toml" ] || cp "$repo/config/fifastreet.toml" "$game/fifastreet.toml"

# On a machine that builds for another one (x86-64), Steam is the other's.
steam=no
if [ "${FS_ADD_TO_STEAM:-1}" = 1 ] && [ ${#run[@]} -eq 0 ]; then
    step "Adding FIFA Street to Steam"
    if "$repo/scripts/add-to-steam.sh" "$dir"; then
        steam=yes
    else
        echo "Warning: FIFA Street was not added to Steam; scripts/add-to-steam.sh tries again."
    fi
fi

echo
echo "Done! FIFA Street is in $game."
if [ "$steam" = yes ]; then
    echo "Play it from Steam (\"FIFA Street\" in the library): the handheld's controls reach it only from there."
else
    echo "Play it from Steam (scripts/add-to-steam.sh adds it) so the controls work,"
    echo "or run $game/fifastreet.sh from a terminal."
fi
