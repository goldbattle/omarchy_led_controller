# Tests for extras/asus-aura/led-aura without touching hardware: a fake ENE controller
# stands in for the SMBus, so detection, the register protocol and the "never write flash"
# promise can be checked anywhere. Run: python3 tests/test_led_aura.py
import sys; sys.dont_write_bytecode = True  # keep the plugin dir clean
import importlib.machinery, pathlib, subprocess, types
from typing import Any

# led-aura has no .py extension, so load it by path. Typed as Any because the type checker
# can't follow a module loaded this way; led-aura itself is type-checked directly (/run-tests).
p = str(pathlib.Path(__file__).parent.parent / "extras/asus-aura/led-aura")
aura: Any = types.ModuleType("led_aura")
importlib.machinery.SourceFileLoader("led_aura", p).exec_module(aura)


class FakeEne:
    """An ENE Aura controller at one SMBus address. Registers are 16-bit and reached by first
    writing a byte-swapped pointer to command 0x00, then reading 0x81 or writing 0x01."""

    def __init__(self, addr: int, name: str = "AUMA0-E6K5-0104", leds: int = 7, micron: bool = False) -> None:
        self.addr, self.ptr = addr, 0
        self.mem: dict[int, int] = {}              # register -> value
        self.writes: list[tuple[int, int]] = []    # every (register, value) written, in order
        for i, c in enumerate(name.encode()):
            self.mem[aura.REG_NAME + i] = c
        self.mem[aura.REG_CONFIG + 2] = leds
        if micron:  # Micron RAM answers the same detection test; led-aura must reject it
            for i, c in enumerate(b"Micron"):
                self.mem[aura.REG_MICRON + i] = c

    def read_byte_data(self, addr: int, reg: int) -> int:
        if addr != self.addr:
            raise OSError("no ACK")
        if reg == 0x81:
            return self.mem.get(self.ptr, 0)
        return reg - 0xA0 if 0xA0 <= reg <= 0xAF else 0  # ENE signature: 0xA0+n reads n

    def write_word_data(self, addr: int, reg: int, word: int) -> None:
        assert addr == self.addr and reg == 0x00
        self.ptr = (word & 0xFF) << 8 | word >> 8

    def write_byte_data(self, addr: int, reg: int, val: int) -> None:
        assert addr == self.addr and reg == 0x01
        self.mem[self.ptr] = val
        self.writes.append((self.ptr, val))


# Detection: found where it is, not elsewhere, and Micron RAM is not mistaken for it.
bus = FakeEne(0x4E)
assert aura.is_aura(bus, 0x4E)
assert not aura.is_aura(bus, 0x40)
assert not aura.is_aura(FakeEne(0x4E, micron=True), 0x4E)

# Reading the controller: name, LED count, and which effect table its firmware uses.
a = aura.Aura(bus, 0x4E)
assert (a.name, a.leds, a.effect) == ("AUMA0-E6K5-0104", 7, aura.EFFECT_V2)
assert aura.Aura(FakeEne(0x4E, name="AUMA0-E6K5-0002"), 0x4E).effect == aura.EFFECT_V1

# Setting a colour: every LED gets it, stored in ENE's R, B, G order, plus the mode.
a.set("FF8000", "breathing")
for i in range(7):
    assert [bus.mem[a.effect + 3 * i + k] for k in range(3)] == [0xFF, 0x00, 0x80]
assert bus.mem[aura.REG_MODE] == aura.MODES["breathing"]

# Safety: only the working registers are written, never anything that could reach flash.
allowed = {aura.REG_DIRECT, aura.REG_APPLY, aura.REG_MODE, aura.REG_SPEED, aura.REG_DIRECTION,
           *range(a.effect, a.effect + 3 * a.leds)}
assert {reg for reg, _ in bus.writes} <= allowed

# Bad arguments are refused before any hardware (or root) is needed.
for args in (["set", "nothex", "static"], ["set", "FF0000", "strobe"], ["flash"], []):
    r = subprocess.run(["python3", "-I", p, *args], capture_output=True, text=True)
    assert r.returncode != 0 and "led-aura probe" in r.stderr, args
print("ok")
