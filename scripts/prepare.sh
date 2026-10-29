#!/usr/bin/env bash
# Checks out ReStreet (FIFA Street recompiled) and the ReXGlue SDK commit it
# builds with, applies ReStreet's patches/rexglue-local-changes.patch to the
# SDK, then this repository's patches/sdk/*.patch (what linux-arm64 needs on
# top), and patches/game/*.patch to ReStreet.
#
#   scripts/prepare.sh WORKDIR [RESTREET_REF]
#
# WORKDIR/ReStreet     ReStreet at the commit in upstream.json (or REF),
#                      patched; its recomp project is
#                      Installer/recomp-template (generated/ and out/ there
#                      are left alone)
# WORKDIR/rexglue-sdk  the patched SDK
#
# Run again, it checks out and patches both again; files that end up the same
# keep their times (scripts/keep-times.py), so a build afterwards recompiles
# only what the new patches change. No game files are involved.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mkdir -p "$1" && cd "$1" && pwd)"

field() {
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
        "$repo/upstream.json" "$1"
}
ref="${2:-$(field commit)}"
rs="$work/ReStreet"
sdk="$work/rexglue-sdk"
times="$work/.prepare-times.json"
python3 "$repo/scripts/keep-times.py" save "$times" "$rs" "$sdk"

if [ ! -d "$rs/.git" ]; then
    git clone -q -c core.autocrlf=false "$(field repository)" "$rs"
fi
git -C "$rs" fetch -q origin "$ref" 2>/dev/null || git -C "$rs" fetch -q origin
git -C "$rs" -c advice.detachedHead=false checkout -q --force "$ref"
# Files an earlier patch added; checkout --force leaves them. The generated
# code and the build folder stay.
git -C "$rs" clean -fdq -e generated -e out -- Installer/recomp-template
echo "ReStreet $(git -C "$rs" rev-parse --short HEAD)"

sdk_commit="$(sed -n 's/.*git -C ReXGlue checkout \([0-9a-f]\{40\}\).*/\1/p' "$rs/docs/BUILDING.md" | head -n1)"
if [ "${#sdk_commit}" -ne 40 ]; then
    sdk_commit="$(field sdk_commit)"
    echo "note: no SDK commit found in ReStreet's docs/BUILDING.md; using upstream.json's"
elif [ "$sdk_commit" != "$(field sdk_commit)" ]; then
    echo "note: ReStreet now pins SDK $sdk_commit (upstream.json: $(field sdk_commit))"
fi

if [ ! -d "$sdk/.git" ]; then
    git clone -q -c core.autocrlf=false "$(field sdk_repository)" "$sdk"
fi
git -C "$sdk" fetch -q origin "$sdk_commit" 2>/dev/null || true
git -C "$sdk" -c advice.detachedHead=false checkout -q --force "$sdk_commit"
# Files an earlier patch added; checkout --force leaves them.
git -C "$sdk" clean -fdq -- include src resources cmake
# Initialize ONLY the submodules needed for Android Vulkan build (skip FFmpeg for space)
for sub in cli11 libmspack tomlplusplus simde xxHash spdlog fmt utfcpp imgui sdl3 \
           vulkan-headers vulkan-memory-allocator spirv-headers spirv-tools glslang; do
    if [ ! -d "$sdk/thirdparty/$sub/.git" ]; then
        git -C "$sdk" submodule update --init --depth 1 "thirdparty/$sub" -q || true
    fi
done
echo "ReXGlue SDK $(git -C "$sdk" describe --tags --always)"

git -C "$sdk" apply --whitespace=nowarn "$rs/patches/rexglue-local-changes.patch"
echo "Applied ReStreet's patches/rexglue-local-changes.patch"
for patch in "$repo"/patches/sdk/*.patch; do
    [ -e "$patch" ] || continue
    git -C "$sdk" apply --whitespace=nowarn "$patch"
    echo "Applied ${patch#"$repo"/}"
done

for patch in "$repo"/patches/game/*.patch; do
    [ -e "$patch" ] || continue
    git -C "$rs" apply --whitespace=nowarn "$patch"
    echo "Applied ${patch#"$repo"/}"
done

python3 "$repo/scripts/keep-times.py" restore "$times"
