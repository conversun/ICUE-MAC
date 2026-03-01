# XC7 RGB ELITE LCD — macOS RGB Control Tool

## TL;DR

> **Quick Summary**: Build a Python CLI tool to control RGB lighting and read temperature on the Corsair XC7 ELITE LCD water block. Includes static color, off, rainbow, breathing, and temperature-based color effects. Auto-start via launchd turns LEDs off at boot.
> 
> **Deliverables**:
> - `icue_xc7/` Python package with device communication and effects
> - `icue-xc7` CLI command (installed via pip)
> - `com.cyonsun.icue-xc7.plist` launchd config
> 
> **Estimated Effort**: Medium (4-6 hours)
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Device module → Effects → CLI → launchd

---

## Context

### Verification Results (Phase 1 — COMPLETE ✅)
- Device: VID 0x1B1C, PID 0x0C42, Serial 2329079710067
- Protocol: HID Feature Reports (temp) + Output Reports (RGB)
- Temperature: 35.8°C confirmed
- RGB: 1024-byte buffer [0x02, 0x07, 0x1F, ...], 31 LEDs, `device.write()`
- Turn off: All zeros works ✅ (confirmed by user)
- API: `hid.device()` + `device.open_path()` (NOT `hid.Device()`)
- Python 3.12.12, hidapi 0.15.0, venv at `.venv/`

### User Requirements
- **Effects**: static color, off, rainbow, breathing, temperature-based color
- **Auto-start**: Turn off all lights at boot (one-shot launchd)
- **Tech**: Python CLI tool

---

## Work Objectives

### CLI Interface Design
```
icue-xc7 off                    # Turn off all LEDs
icue-xc7 static FF0000          # Static red (hex color)
icue-xc7 static 0 128 255       # Static color (R G B decimal)
icue-xc7 rainbow                # Rainbow cycle (Ctrl+C to stop)
icue-xc7 breathe FF0000         # Breathing in red (Ctrl+C to stop)
icue-xc7 temp                   # Color based on water temperature (Ctrl+C to stop)
icue-xc7 temp --once            # Read temp, set color, exit
icue-xc7 info                   # Show device info + temperature
```

### Must Have
- All 5 effects working on real hardware
- Graceful Ctrl+C handling (close device properly)
- `pip install -e .` installable
- launchd plist that runs `icue-xc7 off` at login

### Must NOT Have (Guardrails)
- ❌ No LCD commands
- ❌ No GUI / menu bar app
- ❌ No web server or API
- ❌ No config file system (command-line args only)
- ❌ No fan control
- ❌ No over-engineering — simple, flat module structure

---

## Verification Strategy

- **CLI verification**: Run each command on real hardware, verify LED output visually
- **Temperature**: Confirm reading is in plausible range
- **launchd**: Test `launchctl load/unload` cycle

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Foundation — 3 parallel):
├── Task 1: Package structure + device module [quick]
├── Task 2: Static color + off effect [quick]
└── Task 3: Temperature reading + info command [quick]

Wave 2 (Effects — 2 parallel, after Wave 1):
├── Task 4: Rainbow effect (depends: 1) [deep]
└── Task 5: Breathing effect (depends: 1) [deep]

Wave 3 (Integration — 2 parallel, after Wave 2):
├── Task 6: Temperature-based color effect (depends: 3, 1) [quick]
├── Task 7: CLI entry point + pip install (depends: 1-6) [quick]
└── Task 8: launchd auto-start plist (depends: 7) [quick]

Wave FINAL (Verification — 2 parallel):
├── F1: Hardware QA — test all commands on real device [deep]
└── F2: Code quality + install check [quick]
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|-----------|--------|
| 1    | —         | 2-8    |
| 2    | 1         | 7      |
| 3    | 1         | 6, 7   |
| 4    | 1         | 7      |
| 5    | 1         | 7      |
| 6    | 1, 3      | 7      |
| 7    | 1-6       | 8, F1  |
| 8    | 7         | F1     |

---

## TODOs

- [ ] 1. Package Structure + Device Communication Module

  **What to do**:
  Create the package skeleton and the core device module that wraps HID communication.

  File: `icue_xc7/__init__.py` — empty
  File: `icue_xc7/device.py`:
  ```python
  import hid
  import struct

  VID = 0x1B1C
  PID = 0x0C42
  LED_COUNT = 31

  class XC7Device:
      def __init__(self):
          self._dev = None

      def open(self):
          devices = hid.enumerate(VID, PID)
          if not devices:
              raise RuntimeError("XC7 not found. Check USB connection.")
          self._dev = hid.device()
          self._dev.open_path(devices[0]["path"])

      def close(self):
          if self._dev:
              self._dev.close()
              self._dev = None

      def set_rgb(self, colors: list[tuple[int, int, int]]):
          """Set RGB for all LEDs. colors = list of (R, G, B) tuples, length <= 31."""
          buf = bytearray(1024)
          buf[0] = 0x02
          buf[1] = 0x07
          buf[2] = 0x1F
          for i, (r, g, b) in enumerate(colors[:LED_COUNT]):
              buf[3 + i*3] = r
              buf[4 + i*3] = g
              buf[5 + i*3] = b
          self._dev.write(buf)

      def set_all_rgb(self, r: int, g: int, b: int):
          """Set all LEDs to same color."""
          self.set_rgb([(r, g, b)] * LED_COUNT)

      def get_temperature(self) -> float:
          """Read water temperature in Celsius."""
          buf = self._dev.get_feature_report(0x18, 33)
          return struct.unpack('<h', bytes(buf[2:4]))[0] / 10.0

      def __enter__(self):
          self.open()
          return self

      def __exit__(self, *args):
          self.close()
  ```

  File: `icue_xc7/effects.py` — empty placeholder (effects added in later tasks)
  File: `icue_xc7/cli.py` — empty placeholder

  **Acceptance Criteria**:
  - [ ] `icue_xc7/` directory with `__init__.py`, `device.py`, `effects.py`, `cli.py`
  - [ ] `python3 -c "from icue_xc7.device import XC7Device; print('OK')"` succeeds

  **Commit**: NO (wait for Task 2)

---

- [ ] 2. Static Color + Off Effect

  **What to do**:
  Add static and off effects to `icue_xc7/effects.py`:

  ```python
  from icue_xc7.device import XC7Device

  def effect_off(dev: XC7Device):
      dev.set_all_rgb(0, 0, 0)

  def effect_static(dev: XC7Device, r: int, g: int, b: int):
      dev.set_all_rgb(r, g, b)
  ```

  **QA**: Run on real hardware:
  - `effect_static(dev, 0, 255, 0)` → LEDs turn green
  - `effect_off(dev)` → LEDs turn off

  **Commit**: YES — `feat(xc7): add device module with static color and off effects`

---

- [ ] 3. Temperature Reading + Info Command

  **What to do**:
  Add temperature display function and device info:

  ```python
  def show_info(dev: XC7Device):
      temp = dev.get_temperature()
      print(f"Device: Corsair XC7 ELITE LCD")
      print(f"Water Temperature: {temp:.1f}°C")
  ```

  **QA**: Run on real hardware, verify temperature is printed (expect 25-45°C range)

  **Commit**: NO (merge with Task 2 commit)

---

- [ ] 4. Rainbow Effect

  **What to do**:
  Implement rainbow cycling across the 31 LEDs. Use HSV color space, offset each LED by `(360/31)` degrees, rotate the offset over time.

  ```python
  import colorsys
  import time

  def effect_rainbow(dev: XC7Device, speed: float = 1.0):
      """Rainbow cycle. Ctrl+C to stop."""
      offset = 0.0
      while True:
          colors = []
          for i in range(31):
              hue = ((i / 31.0) + offset) % 1.0
              r, g, b = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
              colors.append((int(r*255), int(g*255), int(b*255)))
          dev.set_rgb(colors)
          offset = (offset + 0.01 * speed) % 1.0
          time.sleep(0.03)
  ```

  **QA**: Run on hardware, verify smooth rainbow animation across LEDs. Ctrl+C should exit cleanly.

  **Commit**: YES — `feat(xc7): add rainbow and breathing effects`

---

- [ ] 5. Breathing Effect

  **What to do**:
  Implement breathing (pulse) effect — fade brightness up and down using a sine wave:

  ```python
  import math
  import time

  def effect_breathe(dev: XC7Device, r: int, g: int, b: int, speed: float = 1.0):
      """Breathing pulse. Ctrl+C to stop."""
      t = 0.0
      while True:
          brightness = (math.sin(t) + 1.0) / 2.0  # 0.0 to 1.0
          dev.set_all_rgb(int(r*brightness), int(g*brightness), int(b*brightness))
          t += 0.05 * speed
          time.sleep(0.03)
  ```

  **QA**: Run on hardware with red (255,0,0), verify smooth pulsing. Ctrl+C clean exit.

  **Commit**: NO (merge with Task 4 commit)

---

- [ ] 6. Temperature-Based Color Effect

  **What to do**:
  Map water temperature to color: cold (< 25°C) = blue, warm (25-35°C) = green, hot (> 40°C) = red. Linear interpolation between.

  ```python
  def temp_to_color(temp: float) -> tuple[int, int, int]:
      """Map temperature to RGB: blue(cold) → green(warm) → red(hot)."""
      if temp <= 25:
          return (0, 0, 255)
      elif temp <= 35:
          t = (temp - 25) / 10.0
          return (0, int(255*(1-t)), int(255*t))  # blue → green
      elif temp <= 45:
          t = (temp - 35) / 10.0
          return (int(255*t), int(255*(1-t)), 0)  # green → red
      else:
          return (255, 0, 0)

  def effect_temp(dev: XC7Device, once: bool = False):
      """Color based on temperature. Ctrl+C to stop."""
      while True:
          temp = dev.get_temperature()
          r, g, b = temp_to_color(temp)
          dev.set_all_rgb(r, g, b)
          print(f"\rTemp: {temp:.1f}°C → RGB({r},{g},{b})", end="", flush=True)
          if once:
              print()
              break
          time.sleep(2.0)
  ```

  **QA**: Run on hardware, verify color changes reflect temperature.

  **Commit**: YES — `feat(xc7): add temperature-based color effect`

---

- [ ] 7. CLI Entry Point + pip install

  **What to do**:
  Create the CLI using argparse and make it pip-installable.

  File: `icue_xc7/cli.py`:
  ```python
  import argparse
  import signal
  import sys
  from icue_xc7.device import XC7Device
  from icue_xc7 import effects

  def parse_color(args) -> tuple:
      # Support: "FF0000" or "255 0 0"
      ...

  def main():
      parser = argparse.ArgumentParser(prog="icue-xc7", description="Corsair XC7 RGB Control")
      sub = parser.add_subparsers(dest="command", required=True)
      sub.add_parser("off", help="Turn off all LEDs")
      sub.add_parser("info", help="Show device info + temperature")
      p_static = sub.add_parser("static", help="Set static color")
      p_static.add_argument("color", nargs="+", help="Hex (FF0000) or R G B (255 0 0)")
      p_rainbow = sub.add_parser("rainbow", help="Rainbow cycle")
      p_rainbow.add_argument("--speed", type=float, default=1.0)
      p_breathe = sub.add_parser("breathe", help="Breathing effect")
      p_breathe.add_argument("color", nargs="+")
      p_breathe.add_argument("--speed", type=float, default=1.0)
      p_temp = sub.add_parser("temp", help="Temperature-based color")
      p_temp.add_argument("--once", action="store_true")

      args = parser.parse_args()

      with XC7Device() as dev:
          signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
          # dispatch to effect based on args.command
          ...
  ```

  File: `pyproject.toml`:
  ```toml
  [build-system]
  requires = ["setuptools"]
  build-backend = "setuptools.backends._legacy:_Backend"

  [project]
  name = "icue-xc7"
  version = "0.1.0"
  dependencies = ["hidapi"]

  [project.scripts]
  icue-xc7 = "icue_xc7.cli:main"
  ```

  **QA**: `pip install -e .` then `icue-xc7 --help` shows usage.

  **Commit**: YES — `feat(xc7): add CLI entry point and pyproject.toml`

---

- [ ] 8. launchd Auto-Start (Off at Boot)

  **What to do**:
  Create `com.cyonsun.icue-xc7.plist` for launchd:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.cyonsun.icue-xc7</string>
      <key>ProgramArguments</key>
      <array>
          <string>/Users/cyonsun/Documents/Code/ICUE-MAC/.venv/bin/icue-xc7</string>
          <string>off</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>StandardOutPath</key>
      <string>/tmp/icue-xc7.log</string>
      <key>StandardErrorPath</key>
      <string>/tmp/icue-xc7.err</string>
  </dict>
  </plist>
  ```

  Print install instructions:
  ```
  cp com.cyonsun.icue-xc7.plist ~/Library/LaunchAgents/
  launchctl load ~/Library/LaunchAgents/com.cyonsun.icue-xc7.plist
  ```

  **QA**: Load plist, verify LEDs turn off.

  **Commit**: YES — `feat(xc7): add launchd auto-start configuration`

---

## Final Verification Wave

- [ ] F1. **Hardware QA** — `deep`
  Test every command on real hardware:
  - `icue-xc7 off` → LEDs off
  - `icue-xc7 static FF0000` → red
  - `icue-xc7 static 0 255 0` → green
  - `icue-xc7 rainbow` → animated rainbow (5 sec then Ctrl+C)
  - `icue-xc7 breathe 0000FF` → blue breathing (5 sec then Ctrl+C)
  - `icue-xc7 temp --once` → shows temp + sets color
  - `icue-xc7 info` → prints device info + temp
  - launchd load/unload cycle
  Output: `Commands [N/7 pass] | launchd [PASS/FAIL] | VERDICT`

- [ ] F2. **Code Quality** — `quick`
  Check: no TODOs, valid Python syntax, pip install -e . works, icue-xc7 --help works.
  Output: `Syntax [OK] | Install [OK] | Help [OK] | VERDICT`

---

## Commit Strategy

- **After T2+T3**: `feat(xc7): add device module with static color and off effects`
- **After T4+T5**: `feat(xc7): add rainbow and breathing effects`
- **After T6**: `feat(xc7): add temperature-based color effect`
- **After T7**: `feat(xc7): add CLI entry point and pyproject.toml`
- **After T8**: `feat(xc7): add launchd auto-start configuration`

## Success Criteria

```bash
icue-xc7 off        # LEDs off
icue-xc7 static FF0000  # Red
icue-xc7 rainbow    # Animated rainbow
icue-xc7 breathe 00FF00  # Green breathing
icue-xc7 temp       # Color by temperature
icue-xc7 info       # Print temp
launchctl load ~/Library/LaunchAgents/com.cyonsun.icue-xc7.plist  # Auto off at boot
```
