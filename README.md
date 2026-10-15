# fifa-street-arm64

[ReStreet](https://github.com/samuelit0davila/fifa-street-pc-port), FIFA
Street (2012, Xbox 360) recompiled with the
[ReXGlue SDK](https://github.com/rexglue/rexglue-sdk), running natively on
ARM64 Linux handhelds such as the Retroid Pocket 6 with ArmadaOS, the way
[pinyon-shift-arm64](https://github.com/Ken5998/pinyon-shift-arm64) and
[saints-reborn-arm64](https://github.com/Ken5998/saints-reborn-arm64) do for
Pinyon Shift and Saints Reborn.

**Status:** the ReXGlue SDK with ReStreet's patch and the Vulkan backend, and
the game with its two recompiled modules, build for linux-arm64; CI checks
both natively on ARM64 and cross-compiled on x86-64. It has not yet been
played on a handheld: the first build from a disc on the Retroid Pocket 6 is
next. ReStreet itself is offline only, so this port is too.

This repository is an overlay: patches, scripts and CI only. It never
contains the game, files extracted from your disc, or the code and binaries
generated from them, and none may be published here.

## What is here

| Path | What it does |
| --- | --- |
| `upstream.json` | The ReStreet commit and the SDK commit it pins, last verified here, and the disc extractor's source. |
| `toolchain.json` | LLVM 20.1.8, CMake, Ninja and the ARM64 sysroot from pinyon-shift-arm64, with their checksums. |
| `cmake/toolchains/linux-arm64.cmake` | Builds for aarch64 Linux against that sysroot, natively or from x86-64. |
| `patches/sdk/` | What linux-arm64 needs on top of ReStreet's `patches/rexglue-local-changes.patch`: the AArch64 fixes and Adreno tuning from the Saints Reborn port, two build fixes, and loading the game's recompiled modules as `lib*.so`. |
| `patches/game/` | ReStreet's recomp project for linux-arm64: codegen run by the build script, and Turnip without shader preambles. |
| `config/` | `fifastreet.sh`, which starts the game with the settings ReStreet's Windows launcher passes for Vulkan, and `fifastreet.toml`, the settings for the Retroid Pocket 6. |
| `launcher/` | The launcher window (Rust, egui): runs `scripts/build.sh` from a fresh copy of this repository, then plays the game or adds it to Steam. |
| `scripts/build.sh ISO\|- [DIR]` | Everything below, from your disc to a game folder ready to play (`-` reuses the game files already extracted). |
| `scripts/fetch-toolchain.sh DEST` | Downloads and checks the toolchain. |
| `scripts/prepare.sh WORKDIR [REF]` | Checks out ReStreet and its SDK commit and applies all the patches; files that come out the same keep their times (`scripts/keep-times.py`), so rebuilds stay small. |
| `scripts/build-sdk.sh SDK TOOLCHAIN` | Builds and installs the SDK for linux-arm64 with Vulkan. |
| `scripts/build-game.sh PROJECT SDK TOOLCHAIN` | Builds the game and its two modules from the recompiled code. |
| `scripts/add-to-steam.sh [DIR]` | Adds the built game to Steam with its artwork (`tools/steam_art.cpp` draws it, `scripts/add-to-steam.py` writes the entry). |
| `scripts/placeholder-codegen.py PROJECT SDK` | Stand-in recompiled code, so CI can build the game without it (the result does not run). |
| `scripts/package-launcher.sh [OUT]` | Builds the launcher and packs it for a release. |
| `.github/workflows/ci.yml` | All of it without game files, natively on an ARM64 runner in Fedora 44 (the base of ArmadaOS) and cross-compiled on x86-64; the launcher on ARM64, with its window opened on a virtual screen. |
| `.github/workflows/release.yml` | Publishes the launcher for ARM64 Linux as a release. |

## Building the game

You need your own FIFA Street (2012) disc image for Xbox 360, and the
handheld needs `git`, `python3`, `curl`, `tar` and `xz`, as ArmadaOS has. The
build takes about 30 GB of space and can take an hour or more, so keep the
handheld on its charger.

ReStreet was made for three versions of the game's modules; its other
versions may not recompile or run correctly.

### With the launcher

1. In Desktop Mode, download `FifaStreet-Launcher-linux-arm64.tar.gz` from
   [Releases](https://github.com/Ken5998/fifa-street-arm64/releases/latest)
   and unpack it.
2. Start `FifaStreet/fifastreet-launcher`. It looks for disc images in your
   home folder, Downloads, ROM folders and SD cards; **Browse...** picks
   another one.
3. Press **Build**. It fetches this repository's scripts and patches and runs
   `scripts/build.sh` (below); **Details** shows its output. When it is done,
   **FIFA Street** is in the Steam library.

Later, **Update** gets the latest fixes and rebuilds only what they change;
the disc is not read again. **Cancel** or closing the window stops a build,
and the next one goes on from there. The launcher's log is
`~/.local/share/FifaStreet-arm64/launcher.log`.

### From a terminal

In Desktop Mode:

```bash
git clone https://github.com/Ken5998/fifa-street-arm64
fifa-street-arm64/scripts/build.sh "/path/to/FIFA Street.iso"
```

It downloads the toolchain, builds the SDK, extracts the game from the disc,
recompiles its three modules (the game, its main DLL and the World Tour
competition engine) and builds them; run it again to resume, finished steps
are skipped. The game ends up in `~/.local/share/FifaStreet-arm64/game`, with
the files from the disc in `GameData` beside it: the same folders the
launcher uses, so either one can update a game the other built.

To update, pull this repository and run the same command again: only what
the new patches change is recompiled.

At the end it adds **FIFA Street** to the Steam library as a non-Steam game
(native, no Proton) with its artwork, drawn from the box art, title screen
and icon in ReStreet's repository. Steam is closed for a moment and started
again, since it would otherwise overwrite the new entry; when the entry is
already there it is left alone, launch options included.

Start the game from Steam: on ArmadaOS the handheld's controls reach a game
only when Steam launches it. For the GPU driver, Armada Control >
Compatibility > Advanced > Drivers > Turnip **Devel** is the one that gave
Pinyon Shift its best performance.

On x86-64 Linux, `build.sh` works the same with `qemu-user` installed (CMake,
Ninja and `wayland-scanner` too); copy the `game` and `GameData` folders to
the handheld, side by side.

## Settings

`game/fifastreet.toml` holds the settings; the build puts the Retroid Pocket
6 defaults there the first time and leaves your changes alone afterwards.
They are ReStreet's "Balanced" profile without FXAA, plus the GPU tweaks that
helped Saints Reborn on the same Adreno GPU:

- **Resolution**: the game draws 1280 x 720 and the image is stretched to
  the screen. `present_effect = "fsr"` sharpens that with FSR 1 for a small
  GPU cost.
- **Language**: `user_language` (1 English, 3 German, 4 French, 5 Spanish,
  6 Italian).
- **Readback**: `readback_resolve = "some"`, ReStreet's default. `"fast"`
  is lighter (it reads the previous frame); `"full"` is the most compatible.
- The GPU work is sent once per frame, vertex data is read through one texel
  buffer, vertex shaders multiply as plain IEEE floats, and Turnip runs
  without shader preambles (`IR3_SHADER_DEBUG=nopreamble`; launch options in
  Steam can override it, e.g. `IR3_SHADER_DEBUG= %command%`).

`game/fifastreet.sh` starts the game with the image fixes ReStreet's Windows
launcher always passes for Vulkan; its log is `game/Logs/fifastreet.log`.

## License

MIT, like ReStreet. See [NOTICE](NOTICE) for the credits.
