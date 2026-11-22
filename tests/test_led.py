import sys; sys.dont_write_bytecode = True  # keep the plugin dir clean
import importlib.machinery, pathlib, types
from typing import Any

# `led` has no .py extension, so load it by path. Typed as Any because the type checker can't
# follow a module loaded this way; `led` itself is type-checked directly (/run-tests).
p = str(pathlib.Path(__file__).parent.parent / "led")
led: Any = types.ModuleType("led")
importlib.machinery.SourceFileLoader("led", p).exec_module(led)
import tempfile as _tf
led.COLORS = pathlib.Path(_tf.mkdtemp()) / "led-colors.json"  # never touch the real cache

SAMPLE = """0: EVGA GeForce RTX 3080 FTW3 Ultra LHR
  Type:           GPU
  Modes: Off Direct Breathing 'Spectrum Cycle' 'Color Cycle' ['Rainbow Wave'] Wave
1: Corsair Commander Pro
  Type:           LED Strip
  Modes: [Direct] 'Rainbow Wave' 'Color Shift' 'Color Pulse' Static
3: Corsair H150i PRO RGB
  Type:           Cooler
  Modes: [Direct] Blinking 'Color Shift' Pulsing
"""

devs = led.parse(SAMPLE)
assert [d["index"] for d in devs] == [0, 1, 3]
assert devs[0]["modes"][3] == "Spectrum Cycle" and devs[1]["type"] == "LED Strip"
assert [d["active"] for d in devs] == ["Rainbow Wave", "Direct", "Direct"]  # the [bracketed] mode

# stuck: calls whose mode the server didn't take (device 0 reports Rainbow Wave, not Direct)
real_openrgb = led.openrgb
led.openrgb = lambda *a, **k: SAMPLE
assert led.stuck([["-d", "0", "-m", "Direct", "-c", "FF0000"], ["-d", "1", "-m", "Direct", "-c", "FF0000"],
                  ["-d", "3", "-m", "Direct", "-c", "FF0000"]]) == [["-d", "0", "-m", "Direct", "-c", "FF0000"]]
led.openrgb = lambda *a, **k: "error: openrgb -ld didn't answer (twice, 5s each)"
assert led.stuck([["-d", "0", "-m", "Direct", "-c", "FF0000"]]) == []  # no read-back: no retry
led.openrgb = real_openrgb

assert led.build(devs, "FF8000", "static", 50) == [
    ["-d", "0", "-m", "Direct", "-c", "804000"],
    ["-d", "1", "-m", "Direct", "-c", "804000"],
    ["-d", "3", "-m", "Direct", "-c", "804000"]]
# gamma: theme peach stays saturated on LEDs, pure colours untouched
assert led.build(devs[:1], "F38D70", "static", 100, 2.2)[0][-1] == "E5452A"
assert led.build(devs[:1], "FF0000", "static", 100, 2.2)[0][-1] == "FF0000"
assert led.build(devs[:1], "F38D70", "static", 100, led.DEFAULTS["gamma"])[0][-1] == "DF3119"  # default: deeper
assert [c[3] for c in led.build(devs, "FF0000", "breathing", 100)] == ["Breathing", "Color Pulse", "Pulsing"]
assert led.build(devs, "FF0000", "rainbow", 100) == [
    ["-d", "0", "-m", "Spectrum Cycle"], ["-d", "1", "-m", "Rainbow Wave"], ["-d", "3", "-m", "Color Shift"]]
# GPU has hardware Off; Corsair devices get painted black
assert led.build(devs, "FFFFFF", "off", 100) == [
    ["-d", "0", "-m", "Off"],
    ["-d", "1", "-m", "Direct", "-c", "000000"],
    ["-d", "3", "-m", "Direct", "-c", "000000"]]

# which devices are lit: power, per-device switch, night hold, monitors off
GPU, CMD, AIO = (d["name"] for d in devs)
cfg = dict(led.DEFAULTS, disabled=[CMD])
def names(held: bool, idle: bool = False) -> list[str]:
    return [d["name"] for d in led.lit(cfg, {"held": held, "idle": idle}, devs)]
assert names(False) == [GPU, AIO]          # Commander switched off
assert names(True) == []                   # night: everything dark
assert names(False, idle=True) == []       # monitors off: everything dark
cfg["idle_off"] = False
assert names(False, idle=True) == [GPU, AIO]  # ...unless the Advanced toggle is off
cfg["idle_off"] = True
cfg["power"] = False
assert names(False) == []                  # global off beats everything

# device switch after "all off" lights just that device; normal toggles keep the others
every = {GPU, CMD, AIO}
c, r = dict(led.DEFAULTS, power=False, disabled=[CMD]), {"held": False}
led.switch_device(c, r, every, AIO, True)
assert c["power"] and set(c["disabled"]) == {GPU, CMD} and [d["name"] for d in led.lit(c, r, devs)] == [AIO]
led.switch_device(c, r, every, GPU, True)
assert c["disabled"] == [CMD]                            # now just adds GPU back
led.switch_device(c, r, every, GPU, False)
assert set(c["disabled"]) == {CMD, GPU}
c, r = dict(led.DEFAULTS), {"held": True}                # night hold: switching on lifts it
led.switch_device(c, r, every, GPU, True)
assert not r["held"] and [d["name"] for d in led.lit(c, r, devs)] == [GPU, CMD, AIO]

# night window, wrapping midnight and not
assert led.in_window("23:00", "22:00", "09:00") and led.in_window("08:59", "22:00", "09:00")
assert not led.in_window("09:00", "22:00", "09:00") and not led.in_window("21:59", "22:00", "09:00")
assert led.in_window("13:00", "12:00", "14:00") and not led.in_window("14:00", "12:00", "14:00")
assert not led.in_window("12:00", "12:00", "12:00")

# flux: sun position, colour temperature, and the curve
from datetime import datetime, timezone
# LA, June solstice ~solar noon: 90 - 34.05 + 23.44 = 79.4 deg; equator at equinox noon ~ overhead
assert abs(led.sun_elevation(datetime(2024, 6, 21, 19, 57, tzinfo=timezone.utc), 34.05, -118.24) - 79.4) < 0.5
assert led.sun_elevation(datetime(2024, 3, 20, 12, 7, tzinfo=timezone.utc), 0, 0) > 88
assert led.sun_elevation(datetime(2024, 6, 21, 8, 0, tzinfo=timezone.utc), 34.05, -118.24) < -20  # LA 1am
assert led.kelvin(6500) == [255, 254, 250] and led.kelvin(1900) == [255, 132, 0]
assert led.flux(30) == (led.flux(6)[0], "6500K")             # daytime: white
assert led.flux(0)[1] == "3400K" and led.flux(-6)[1] == "1900K"
assert led.flux(1.5)[1] == "4200K"                           # warming toward sunset
assert led.flux(-9)[1] == "1900K→red" and led.flux(-9)[0] == "FF4200"
assert led.flux(-12) == ("FF0000", "red") and led.flux(-40) == ("FF0000", "red")

# theme colour: the accent from colors.toml, never keyboard.rgb
import tempfile
with tempfile.TemporaryDirectory() as d:
    led.THEME = pathlib.Path(d)
    assert led.theme_color() == "FFFFFF"
    (led.THEME / "colors.toml").write_text('mode = "dark"\naccent = "#f38d70"\n')
    assert led.theme_color() == "F38D70"
    (led.THEME / "keyboard.rgb").write_text("#ff00ff\n")  # tokyo-night style override: ignored
    assert led.look(dict(led.DEFAULTS, color="theme")) == ("F38D70", "static")
    # chromium.theme: Omarchy's default is the background (ignored); a theme's own tint wins
    (led.THEME / "colors.toml").write_text('accent = "#56949f"\nbackground = "#faf4ed"\n')
    (led.THEME / "chromium.theme").write_text("250,244,237\n")
    assert led.theme_color() == "56949F"
    (led.THEME / "chromium.theme").write_text("210,196,219\n")       # rose-pine lavender
    assert led.theme_color() == "D2C4DB"
    (led.THEME / "chromium.theme").write_text("0,23,46\n")           # retro-82: dark shade, not a tint
    assert led.theme_color() == "56949F"
    (led.THEME / "chromium.theme").write_text("garbage\n")
    assert led.theme_color() == "56949F"
    # palette slots: "theme:magenta" follows that slot; a missing slot falls back to "theme"
    (led.THEME / "colors.toml").write_text('accent = "#56949f"\nmagenta = "#907aa9"\nbackground = "#faf4ed"\n')
    assert led.theme_palette()["magenta"] == "907AA9"
    assert led.look(dict(led.DEFAULTS, color="theme:magenta")) == ("907AA9", "static")
    assert led.look(dict(led.DEFAULTS, color="theme:green")) == ("56949F", "static")
    assert led.hex_color("theme:magenta") == "theme:magenta"
    try:
        led.hex_color("theme:brown")
        raise AssertionError("brown is not offered")
    except ValueError:
        pass
    assert led.theme_name() == ""                         # no theme.name next to the theme dir
    (pathlib.Path(d) / "theme.name").write_text("tokyo-night\n")
    led.THEME = pathlib.Path(d) / "theme"
    assert led.theme_name() == "tokyo-night"

# motherboard (aura) devices: skipped by the OpenRGB builder, driven through led-aura by sync
board: dict[str, Any] = {"index": None, "name": "ASUS PRIME X299-A", "type": "Motherboard", "backend": "aura", "modes": []}
assert led.build(devs[:1] + [board], "FF0000", "static", 100) == [["-d", "0", "-m", "Direct", "-c", "FF0000"]]
sent: list[tuple[str, str]] = []
applied: list[list[str]] = []
led.aura_set, real_apply = (lambda c, m: sent.append((c, m))), led.apply
led.apply = lambda calls, counts, names: applied.extend(calls)
led.stuck, real_stuck = (lambda calls: []), led.stuck  # every mode took
cfg2 = dict(led.DEFAULTS, color="F38D70", brightness=50, gamma=2.8)
led.sync(cfg2, {"held": False}, devs[:1] + [board])
assert sent == [(led.adjust("F38D70", 50, 2.8), "static")] and len(applied) == 1
sent.clear()
led.sync(dict(cfg2, disabled=[board["name"]]), {"held": False}, devs[:1] + [board])
assert sent == [("000000", "off")]                      # switched off -> board dark
# rate limit: a change waits until MIN_GAP after the previous one finished, and stamps its own
naps: list[float] = []
real_sleep, real_now = led.time.sleep, led.time.time
led.time.sleep, led.time.time = naps.append, lambda: 1000.0
rt3: dict[str, Any] = {"held": False, "synced": 999.7}
led.sync(cfg2, rt3, devs[:1])
assert len(naps) == 1 and abs(naps[0] - (led.MIN_GAP - 0.3)) < 1e-9 and rt3["synced"] == 1000.0
naps.clear()
led.sync(cfg2, {"held": False, "synced": 990.0}, devs[:1])  # long ago: no wait
assert naps == []
led.time.sleep, led.time.time = real_sleep, real_now
led.apply, led.stuck = real_apply, real_stuck

# screens_off: dark only when every enabled monitor is DPMS-off; unknown -> never dark
import subprocess as sp
def fake_hyprctl(mons: list[dict[str, Any]]) -> None:
    led.subprocess.run = lambda *a, **k: sp.CompletedProcess(a, 0, stdout=__import__("json").dumps(mons))
real_run = led.subprocess.run
fake_hyprctl([{"dpmsStatus": False}, {"dpmsStatus": False}, {"dpmsStatus": True, "disabled": True}])
assert led.screens_off()
fake_hyprctl([{"dpmsStatus": False}, {"dpmsStatus": True}])
assert not led.screens_off()
fake_hyprctl([])
assert not led.screens_off()
led.subprocess.run = lambda *a, **k: sp.CompletedProcess(a, 1, stdout="")
assert not led.screens_off()
def hang(*a: Any, **k: Any) -> Any:
    raise sp.TimeoutExpired("openrgb", 5)
led.subprocess.run = hang
tries: list[int] = []
def hang_then_answer(*a: Any, **k: Any) -> Any:
    tries.append(1)
    if len(tries) == 1:
        raise sp.TimeoutExpired("openrgb", 5)
    return sp.CompletedProcess(a, 0, stdout="0: GPU\n", stderr="")
led.subprocess.run = hang_then_answer
assert led.openrgb("-ld") == "0: GPU\n" and len(tries) == 2  # a hung run is replaced once
led.subprocess.run = hang
assert led.openrgb("-ld") == "error: openrgb -ld didn't answer (twice, 5s each)"
led.subprocess.run = real_run

# apply: every device in one openrgb run; modes that want N colours are learned once
calls: list[list[str]] = []
def fake_openrgb(*a: str) -> str:
    """Like openrgb: Commander "Color Pulse" and H150i "Color Shift" insist on 2 colours,
    and the first block that breaks that ends the whole run."""
    calls.append(list(a))
    blocks = " ".join(a).split("-d ")[1:]
    for b in blocks:
        if ("Color Pulse" in b or "Color Shift" in b) and b.count(",") != 1:
            return "Wrong number of colors specified for mode X\nPlease provide between 2 and 2 colors"
    return ""
led.openrgb = fake_openrgb
counts: dict[str, int] = {}
index_names = {"0": "GPU", "1": "Commander", "3": "H150i"}
batch = [["-d", "0", "-m", "Direct", "-c", "FF0000"], ["-d", "1", "-m", "Color Pulse", "-c", "FF0000"],
         ["-d", "3", "-m", "Color Shift"]]
led.apply([list(c) for c in batch], counts, index_names)
assert counts == {"Commander:Color Pulse": 2, "H150i:Color Shift": 2}  # learned the first time
calls.clear()
led.apply([list(c) for c in batch], counts, index_names)
assert calls == [["-d", "0", "-m", "Direct", "-c", "FF0000", "-d", "1", "-m", "Color Pulse", "-c", "FF0000,FF0000",
                  "-d", "3", "-m", "Color Shift", "-c", "FF0000,0000FF"]]  # then one run for all
calls.clear()
led.apply([], counts, index_names)
assert calls == []  # nothing to send: no openrgb run at all
# colour names for the panel header: every preset swatch, plus custom colours
names_of = {"FFFFFF": "white", "FF0000": "red", "FF6000": "orange", "FFC000": "yellow", "00FF00": "green",
            "00FFFF": "cyan", "0000FF": "blue", "8000FF": "purple", "FF00A0": "pink"}
for hexc, name in names_of.items():
    assert led.color_name(hexc) == name, (hexc, led.color_name(hexc))
assert led.color_name("F38D70") == "pale red" and led.color_name("000000") == "black"
assert led.color_name("808080") == "grey" and led.color_name("FF2A00") == "red"

# lock: a second led waits until the first one is done
import fcntl, tempfile as tf
with tf.TemporaryDirectory() as d:
    led.LOCK = pathlib.Path(d) / "led.lock"
    held = led.lock()
    probe = open(led.LOCK, "w")
    try:
        fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
        raise AssertionError("lock was not held")
    except BlockingIOError:
        pass
    held.close()
    fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)  # free again once released
    probe.close()
print("ok")
