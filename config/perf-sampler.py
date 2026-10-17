#!/usr/bin/env python3
"""Writes the CPU use of the game's busiest threads to Logs/perf.log every
5 seconds while the game runs, to tell which thread (if any) holds the frame
rate. fifastreet.sh starts it when a file named perf_log is next to the game.

    perf-sampler.py PID LOG
"""
import os
import sys
import time
from pathlib import Path

INTERVAL = 5.0
TOP = 12
TICKS = os.sysconf("SC_CLK_TCK")


def threads(pid: str) -> dict[str, tuple[str, int, int, int]]:
    """tid -> (name, CPU ticks, core it last ran on, voluntary switches)."""
    out = {}
    for task in Path(f"/proc/{pid}/task").iterdir():
        try:
            stat = (task / "stat").read_text()
            status = (task / "status").read_text()
        except OSError:
            continue
        name = stat[stat.index("(") + 1:stat.rindex(")")]
        fields = stat[stat.rindex(")") + 2:].split()
        waits = next((int(line.split()[1]) for line in status.splitlines()
                      if line.startswith("voluntary_ctxt_switches")), 0)
        out[task.name] = (name, int(fields[11]) + int(fields[12]), int(fields[36]), waits)
    return out


def gpu_clock() -> str:
    for device in sorted(Path("/sys/class/devfreq").glob("*")):
        if "gpu" not in device.name and "kgsl" not in device.name:
            continue
        try:
            current = int((device / "cur_freq").read_text()) // 1000000
            highest = int((device / "max_freq").read_text()) // 1000000
        except (OSError, ValueError):
            continue
        return f"GPU clock {current}/{highest} MHz"
    return "GPU clock unknown"


def core_clocks() -> str:
    clocks = []
    for cpu in sorted(Path("/sys/devices/system/cpu").glob("cpu[0-9]*"), key=lambda p: int(p.name[3:])):
        try:
            clocks.append(str(int((cpu / "cpufreq/scaling_cur_freq").read_text()) // 1000))
        except (OSError, ValueError):
            clocks.append("-")
    return "core MHz " + " ".join(clocks)


def main(pid: str, log: str) -> int:
    before, start = threads(pid), time.monotonic()
    with open(log, "w", buffering=1) as out:
        out.write(f"CPU use per thread every {INTERVAL:.0f} s; 100% = one whole core\n")
        while Path(f"/proc/{pid}").exists():
            time.sleep(INTERVAL)
            try:
                now, end = threads(pid), time.monotonic()
            except OSError:
                break
            seconds = end - start
            rows = []
            for tid, (name, ticks, core, waits) in now.items():
                old = before.get(tid, (name, ticks, core, waits))
                percent = (ticks - old[1]) * 100.0 / TICKS / seconds
                rows.append((percent, name, tid, core, int((waits - old[3]) / seconds)))
            rows.sort(reverse=True)
            total = sum(r[0] for r in rows)
            out.write(f"\n{time.strftime('%H:%M:%S')} total {total:.0f}% over {len(rows)} threads; "
                      f"{gpu_clock()}; {core_clocks()}\n")
            for percent, name, tid, core, waits in rows[:TOP]:
                out.write(f"  {percent:5.1f}%  core {core}  {waits:6d} waits/s  {name} ({tid})\n")
            before, start = now, end
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
