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

# which devices are lit: power, per-device switch, night hold, keep_on
GPU, CMD, AIO = (d["name"] for d in devs)
cfg = dict(led.DEFAULTS, disabled=[CMD], keep_on=[AIO])
names = lambda held: [d["name"] for d in led.lit(cfg, held, devs)]
assert names(False) == [GPU, AIO]          # Commander switched off
assert names(True) == [AIO]                # night: only keep_on survives, still minus disabled
cfg["power"] = False
assert names(False) == []                  # global off beats everything

# night window, wrapping midnight and not
assert led.in_window("23:00", "22:00", "09:00") and led.in_window("08:59", "22:00", "09:00")
assert not led.in_window("09:00", "22:00", "09:00") and not led.in_window("21:59", "22:00", "09:00")
assert led.in_window("13:00", "12:00", "14:00") and not led.in_window("14:00", "12:00", "14:00")
assert not led.in_window("12:00", "12:00", "12:00")

# daylight fade: keyframes hold, interpolate, and wrap past midnight
K = led.DEFAULTS["daylight"]
assert led.daylight("12:00", K) == "0040FF"           # midday blue
assert led.daylight("17:00", K) == "0040FF" and led.daylight("19:00", K) == "FF6000"
assert led.daylight("18:00", K) == "805080"           # halfway blue -> orange
assert led.daylight("02:00", K) == "FF0000"           # night red, across midnight
assert led.daylight("07:00", K) == "802080"           # sunrise halfway red -> blue
assert led.daylight("05:00", [["06:00", "000000"]]) == "000000"  # single keyframe

# theme colour: keyboard.rgb wins, colors.toml accent is the fallback
import tempfile
with tempfile.TemporaryDirectory() as d:
    led.THEME = pathlib.Path(d)
    assert led.theme_color() == "FFFFFF"
    (led.THEME / "colors.toml").write_text('mode = "dark"\naccent = "#f38d70"\n')
    assert led.theme_color() == "F38D70"
    (led.THEME / "keyboard.rgb").write_text("#00ff00\n")
    assert led.theme_color() == "00FF00"
    assert led.look(dict(led.DEFAULTS, color="theme")) == ("00FF00", "static")

# retry path: fake openrgb that demands 2 colours the first time
calls = []
led.openrgb = lambda *a: calls.append(list(a)) or ("Please provide between 2 and 2 colors" if len(calls) == 1 else "")
led.apply(["-d", "1", "-m", "Color Pulse", "-c", "FF0000"])
assert calls[1][-1] == "FF0000,FF0000"
print("ok")
