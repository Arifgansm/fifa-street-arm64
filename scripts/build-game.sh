#!/usr/bin/env bash
# Builds FIFA Street for linux-arm64 (the fifastreet program and its two
# recompiled guest modules, libfifastreet_*_xex.so) from ReStreet's recomp
# project, against the SDK that build-sdk.sh installed: natively on aarch64,
# or cross-compiled on x86-64.
#
#   scripts/build-game.sh PROJECT SDK_INSTALL TOOLCHAIN [BUILD]
#
# PROJECT      ReStreet's Installer/recomp-template, made by prepare.sh, with
#              PROJECT/generated holding what `rexglue codegen` made from the
#              game (or placeholder-codegen.py's stand-in, to check the build
#              without the game)
# SDK_INSTALL  build-sdk.sh's install prefix (SDK/out/install/linux-arm64)
# TOOLCHAIN    fetch-toolchain.sh's folder
# BUILD        build folder (default PROJECT/out/linux-arm64)
#
# Parallel jobs: FS_JOBS, else one per logical CPU but at most one per 2 GB of
# memory (the recompiled files are huge).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
project="$(cd "$1" && pwd)"
sdk="$(cd "$2" && pwd)"
export FS_ARM64_TOOLCHAIN="$(cd "$3" && pwd)"
build="${4:-$project/out/linux-arm64}"
llvm="$FS_ARM64_TOOLCHAIN/llvm/bin"
export PATH="$FS_ARM64_TOOLCHAIN/bin:$PATH"

if [ -n "${FS_JOBS:-}" ]; then
    jobs="$FS_JOBS"
else
    mem_gb=$(( $(sed -n 's/^MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo) / 1048576 ))
    jobs=$(( mem_gb / 2 ))
    [ "$jobs" -le "$(nproc)" ] || jobs="$(nproc)"
    [ "$jobs" -ge 1 ] || jobs=1
fi
echo "Building with $jobs parallel jobs ($(nproc) CPU threads)"

# find_package(rexglue) looks only inside the sysroot and the SDK
# (CMAKE_FIND_ROOT_PATH); "/" makes it search the SDK's lib/cmake there.
cmake -S "$project" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchains/linux-arm64.cmake" \
    "-DCMAKE_C_COMPILER=$llvm/clang" "-DCMAKE_CXX_COMPILER=$llvm/clang++" \
    "-DCMAKE_FIND_ROOT_PATH=$sdk" -DCMAKE_PREFIX_PATH=/ \
    -DREXGLUE_EXTERNAL_CODEGEN=ON -DREXGLUE_RECOMP_DEBUG_INFO=none
cmake --build "$build" --parallel "$jobs"

for f in "$build/fifastreet" "$build/libfifastreet_fifadllzf_xex.so" \
         "$build/libfifastreet_FootballCompEngzf_xex.so"; do
    # ELF machine 183 (0xb7): AArch64.
    [ "$(od -An -tx1 -j18 -N2 "$f" | tr -d ' \n')" = b700 ] || { echo "error: $f is not aarch64" >&2; exit 1; }
    echo "OK $f (aarch64)"
done
