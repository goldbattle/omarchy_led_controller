#!/usr/bin/env python3
"""Live hardware playbook for omarchy_led_controller.

Drives the installed `led` through effects, colours, brightness, every device switch, all
off/on and the night schedule. After each step it reads back from OpenRGB which mode every
device is really in and compares it with what `led` should have set, so dropped or ignored
changes show up as failures. Works with whatever hardware is attached: the devices come from
`led state` at the start. Your settings are put back at the end, even if a step fails.

  playbook.py            run every step
  playbook.py --watch 3  also pause 3 seconds after each step, so a person can watch the lights

Colours can't be read back from OpenRGB, only modes, so pair it with --watch when colour
matters. Devices driven by an extra (led-aura) have no read-back and are skipped in checks.
"""
import argparse, importlib.machinery, json, shutil, subprocess, sys, tempfile, time, types
from collections.abc import Callable
from functools import partial
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[3]
CONFIG = Path.home() / ".config/led.json"

# Reuse led's own mode tables and parsers (it has no .py extension, so load it by path).
led: Any = types.ModuleType("led")
importlib.machinery.SourceFileLoader("led", str(REPO / "led")).exec_module(led)

State = dict[str, Any]  # what `led state` prints


def run(*args: str) -> State:
    """Run the installed `led` and return the state it prints (fetched if it prints none)."""
    r = subprocess.run(["led", *args], capture_output=True, text=True, timeout=60)
    if r.returncode:
        raise RuntimeError(f"led {' '.join(args)}: {(r.stderr or r.stdout).strip()}")
    return json.loads(r.stdout) if r.stdout.strip() else run("state")


def expected(dev: State, state: State) -> str | None:
    """The mode `led` should have put this device in, given the state it reported."""
    lit = state["power"] and not state["held"] and dev["name"] not in state["disabled"]
    intent = state["mode"] if lit else "off"
    intent = "static" if intent == "flux" else intent  # flux is a static colour that changes slowly
    mode: str | None = led.pick(dev, intent)
    if intent == "off" and not mode:  # no hardware Off: painted black in static
        mode = led.pick(dev, "static")
    return mode


def check(state: State, settle: float) -> list[str]:
    """Every device whose real mode differs from the expected one, after `settle` seconds."""
    time.sleep(settle)
    actual = {d["name"]: d["active"] for d in led.parse(led.openrgb("-ld"))}
    problems = []
    for dev in state["devices"]:
        if dev.get("backend"):  # extras have no read-back
            continue
        want, have = expected(dev, state), actual.get(dev["name"], "missing")
        if want and have != want:
            problems.append(f"{dev['name']} is in {have!r}, expected {want!r}")
    return problems


def hhmm(minutes_from_now: int) -> str:
    return (datetime.now() + timedelta(minutes=minutes_from_now)).strftime("%H:%M")


def steps(devices: list[str]) -> list[tuple[str, Callable[[], State]]]:
    """(description, action) pairs; each action returns the state to check against."""
    s: list[tuple[str, Callable[[], State]]] = [
        ("static red", lambda: run("set", "FF0000", "-m", "static", "-b", "100")),
        ("static blue", lambda: run("set", "0000FF")),
        ("breathing", lambda: run("set", "-m", "breathing")),
        ("rainbow", lambda: run("set", "-m", "rainbow")),
        ("rainbow -> static (dropped-mode regression)", lambda: run("set", "-m", "static")),
        ("rainbow -> static, back to back", lambda: (run("set", "-m", "rainbow"), run("set", "-m", "static"))[1]),
        ("breathing -> rainbow -> breathing", lambda: (run("set", "-m", "rainbow"), run("set", "-m", "breathing"))[1]),
        ("theme colour", lambda: run("set", "theme", "-m", "static")),
        ("flux", lambda: run("set", "-m", "flux")),
        ("dim white, 30%", lambda: run("set", "FFFFFF", "-m", "static", "-b", "30")),
        ("colour depth 1.0", lambda: run("set", "-g", "1.0", "-b", "100")),
    ]
    for name in devices:
        s += [(f"switch off: {name}", partial(run, "device", name, "off")),
              (f"switch on: {name}", partial(run, "device", name, "on"))]
    s += [
        ("all off", lambda: run("off")),
        ("one device on after all off", lambda: run("device", devices[0], "on")),
        ("all on", lambda: run("on")),
        ("night schedule starts", lambda: run("schedule", json.dumps({"auto_off": True, "off": hhmm(-1), "on": hhmm(60)}))),
        ("night schedule turned off", lambda: run("schedule", json.dumps({"auto_off": False}))),
        ("all off while breathing, then on", lambda: (run("set", "-m", "breathing"), run("off"), run("on"))[2]),
    ]
    return s


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--watch", type=float, default=0, metavar="SECONDS", help="extra pause after each step")
    p.add_argument("--settle", type=float, default=1.0, metavar="SECONDS",
                   help="wait before reading modes back (default 1)")
    a = p.parse_args()

    start = run("state")
    devices = [d["name"] for d in start["devices"]]
    skipped = [d["name"] for d in start["devices"] if d.get("backend")]
    print(f"devices: {', '.join(devices)}")
    if skipped:
        print(f"not read back (extras): {', '.join(skipped)}")

    backup = Path(tempfile.mkdtemp()) / "led.json"
    shutil.copy(CONFIG, backup)
    failed = 0
    try:
        for i, (label, action) in enumerate(steps(devices), 1):
            try:
                problems = check(action(), a.settle)
            except RuntimeError as e:
                problems = [str(e)]
            failed += bool(problems)
            print(f"{'PASS' if not problems else 'FAIL'}  {i:2}. {label}")
            for problem in problems:
                print(f"        {problem}")
            time.sleep(a.watch)
    finally:
        shutil.copy(backup, CONFIG)
        run("restore")
        print("settings restored")
    print(f"{failed} step(s) failed" if failed else "all steps passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
