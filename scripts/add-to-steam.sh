#!/usr/bin/env bash
# Adds the game build.sh made to the Steam library, as a non-Steam game that
# runs natively (no Proton), with artwork drawn from the box art, title screen
# and icon in ReStreet's repository. build.sh runs it at the end; run it by
# hand after an earlier build, or again to redo the entry.
#
#   scripts/add-to-steam.sh [DIR]
#
# DIR  build.sh's folder (default ~/.local/share/FifaStreet-arm64)
#
# A running Steam is closed first, since it writes its own copy of the library
# back when it closes, and started again afterwards.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
dir="$(cd "${1:-$HOME/.local/share/FifaStreet-arm64}" && pwd)"
tc="$dir/toolchain"
rs="$dir/ReStreet"
game="$dir/game"
artwork="$dir/artwork"
[ -f "$game/fifastreet.sh" ] || { echo "error: no game in $game: run build.sh first" >&2; exit 1; }

run=()
case "$(uname -m)" in
    aarch64|arm64) ;;
    *) run=("$(command -v qemu-aarch64-static || command -v qemu-aarch64)" -L "$tc/sysroot") ;;
esac

# The artwork: drawn by tools/steam_art.cpp, built with the port's toolchain.
tool="$dir/tools/steam_art"
if [ ! -x "$tool" ] || [ "$repo/tools/steam_art.cpp" -nt "$tool" ]; then
    linker=()
    [ ! -e "$tc/bin/ld.lld" ] || linker=("--ld-path=$tc/bin/ld.lld")
    mkdir -p "$dir/tools"
    "$tc/llvm/bin/clang++" --target=aarch64-linux-gnu "--sysroot=$tc/sysroot" -std=c++17 -O2 \
        -fuse-ld=lld "${linker[@]}" -static-libstdc++ -w \
        -I "$dir/rexglue-sdk/thirdparty/stb" "$repo/tools/steam_art.cpp" \
        -Wl,-Bstatic -lz -Wl,-Bdynamic -o "$tool"
fi
mkdir -p "$artwork"
"${run[@]}" "$tool" "$rs/Launcher/FifaStreetLauncher/cover.jpg" "$rs/docs/images/start-screen.png" \
    "$rs/Installer/recomp-template/src/fifastreet.ico" "$artwork"

python3 "$repo/scripts/add-to-steam.py" "$game" "$artwork"
