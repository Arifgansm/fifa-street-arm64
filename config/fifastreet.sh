#!/usr/bin/env bash
# Starts FIFA Street (linux-arm64) with the settings ReStreet's Windows
# launcher passes for its validated Vulkan configuration. Installed beside the
# game as fifastreet.sh by scripts/build.sh; Steam starts this.
#
# Settings you may want to change are in fifastreet.toml beside it (and the
# in-game settings, Home key or the debug overlay). The variables below win
# over that file, so only what the game needs to look right is set here.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
mkdir -p Logs

# Render path and image fixes ReStreet's launcher always sets for Vulkan
# (they remove the goal-replay blur).
export REX_RENDER_TARGET_PATH_VULKAN=fbo
export REX_DRAW_RESOLUTION_SCALED_TEXTURE_OFFSETS=false
export REX_DEPTH_FLOAT24_CONVERT_IN_PIXEL_SHADER=true
export REX_GAMMA_RENDER_TARGET_AS_UNORM16=false
export REX_SNORM16_RENDER_TARGET_FULL_RANGE=false
export REX_VULKAN_DYNAMIC_RENDERING=false
export REX_HALF_PIXEL_OFFSET=false
export REX_ANISOTROPIC_OVERRIDE=-1
export REX_DIRECT_HOST_RESOLVE=false
# The game keeps its own clock; frames are shown with "true vsync"
# (fifastreet.toml) at the screen's rate.
export REX_GUEST_VBLANK_UNLOCKED=true
export REX_VSYNC=false
# The game's own frame limiter (40 FPS in replays and cutscenes) is raised to
# the video mode's refresh rate, as with VSync on in ReStreet's launcher.
: "${REX_FRAME_LIMITER_MIN_HZ:=auto}"
export REX_FRAME_LIMITER_MIN_HZ
# "auto" reads the rate from the environment only, as the launcher passes it;
# take it from fifastreet.toml (60 if it is not there).
if [ -z "${REX_VIDEO_MODE_REFRESH_RATE:-}" ]; then
    REX_VIDEO_MODE_REFRESH_RATE="$(sed -n 's/^[[:space:]]*video_mode_refresh_rate[[:space:]]*=[[:space:]]*\([0-9.]*\).*/\1/p' \
        "$here/fifastreet.toml" 2>/dev/null | head -n1)"
    export REX_VIDEO_MODE_REFRESH_RATE="${REX_VIDEO_MODE_REFRESH_RATE:-60}"
fi
# Keep only the one synchronous readback that keeps stadium floors clean.
unset REX_READBACK_SOME_SYNC_ADDRS
export REX_READBACK_SOME_SYNC_BELOW=0
export REX_VULKAN_READBACK_SHORT_WAIT=true
export REX_VULKAN_READBACK_SPIN_US=500
export REX_LOG_FILE="$here/Logs/fifastreet.log"

# With a file named perf_log next to the game, Logs/perf.log gets the CPU use
# of the game's busiest threads every 5 seconds (perf-sampler.py). The game
# keeps this script's process id, which exec hands it.
if [ -e "$here/perf_log" ] && [ -f "$here/perf-sampler.py" ] && command -v python3 >/dev/null; then
    python3 -I "$here/perf-sampler.py" "$$" "$here/Logs/perf.log" </dev/null >/dev/null 2>&1 &
fi
exec "$here/fifastreet" --game_data_root="$here/../GameData" "$@"
