import sys; sys.dont_write_bytecode = True  # keep the plugin dir clean
import importlib.machinery, importlib.util, pathlib

p = str(pathlib.Path(__file__).with_name("led"))
spec = importlib.util.spec_from_loader("led", importlib.machinery.SourceFileLoader("led", p))
led = importlib.util.module_from_spec(spec); spec.loader.exec_module(led)

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
names = lambda held, idle=False: [d["name"] for d in led.lit(cfg, {"held": held, "idle": idle}, devs)]
assert names(False) == [GPU, AIO]          # Commander switched off
assert names(True) == []                   # night: everything dark
assert names(False, idle=True) == []       # monitors off: everything dark
cfg["idle_off"] = False
assert names(False, idle=True) == [GPU, AIO]  # ...unless the Advanced toggle is off
cfg["idle_off"] = True
cfg["power"] = False
assert names(False) == []                  # global off beats everything

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
assert led.zone_location() is not None

# theme colour: the accent from colors.toml, never keyboard.rgb
import tempfile
with tempfile.TemporaryDirectory() as d:
    led.THEME = pathlib.Path(d)
    assert led.theme_color() == "FFFFFF"
    (led.THEME / "colors.toml").write_text('mode = "dark"\naccent = "#f38d70"\n')
    assert led.theme_color() == "F38D70"
    (led.THEME / "keyboard.rgb").write_text("#ff00ff\n")  # tokyo-night style override: ignored
    assert led.look(dict(led.DEFAULTS, color="theme")) == ("F38D70", "static")

# screens_off: dark only when every enabled monitor is DPMS-off; unknown -> never dark
import subprocess as sp
def fake_hyprctl(mons):
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
led.subprocess.run = real_run

# retry path: fake openrgb that demands 2 colours the first time
calls = []
led.openrgb = lambda *a: calls.append(list(a)) or ("Please provide between 2 and 2 colors" if len(calls) == 1 else "")
led.apply(["-d", "1", "-m", "Color Pulse", "-c", "FF0000"])
assert calls[1][-1] == "FF0000,FF0000"
calls.clear()  # rainbow fallback without a colour (H150i "Color Shift" wants 2)
led.apply(["-d", "3", "-m", "Color Shift"])
assert calls[1][-2:] == ["-c", "FF0000,0000FF"]
print("ok")
