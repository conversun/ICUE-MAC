# XC7 RGB ELITE LCD — macOS HID Protocol Verification

## TL;DR

> **Quick Summary**: Verify that the Corsair iCUE XC7 RGB ELITE LCD CPU Water Block (VID:0x1B1C PID:0x0C42) can be detected, read from, and written to via USB HID on a Hackintosh. Single Python script, 4 sequential steps, ~150 lines.
> 
> **Deliverables**:
> - `verify_xc7.py` — standalone verification script
> - Terminal output confirming device detection, temperature read, and RGB write
> - User visual confirmation that LEDs changed color
> 
> **Estimated Effort**: Quick (2-3 hours)
> **Parallel Execution**: NO — sequential steps, each depends on previous
> **Critical Path**: Hardware check → Enumerate → Temperature → RGB

---

## Context

### Original Request
User has a Hackintosh with Corsair iCUE XC7 RGB ELITE LCD water block. Wants to control RGB lighting, read temperature, and eventually auto-start at boot. Chose "verify first, then decide" approach before committing to a full implementation.

### Interview Summary
**Key Discussions**:
- User's device: iCUE XC7 RGB ELITE LCD CPU Water Block (USB PID: 0x0C42)
- OpenLinkHub (Go, GPL-3.0) has COMPLETE reverse-engineered protocol for this device
- Protocol uses mixed HID operations: Feature Reports for reads, Output Reports for writes
- User has full dev environment: Homebrew, Go, Python, Xcode
- Feature priorities: RGB control, temperature monitoring, auto-start (NOT LCD)

**Research Findings**:
- OpenLinkHub `src/devices/xc7/xc7.go`: Complete reference implementation
- go-hid wraps HIDAPI which has native macOS support via `hid_darwin.c` (IOKit)
- No existing macOS-native tool supports XC7
- Protocol requires NO initialization handshake — open device and communicate directly

### Metis Review
**Identified Gaps** (addressed):

1. **CRITICAL — Protocol Mischaracterization**: RGB does NOT use Feature Reports. RGB uses `device.write()` (HID Output Report, 1024 bytes). Temperature/firmware use `get_feature_report()` (HID Feature Report, 33 bytes). Plan now correctly distinguishes both.

2. **CRITICAL — Missing Step 0**: Must verify device is visible at USB bus level (`system_profiler`) BEFORE attempting HID access. Hackintosh USB mapping may exclude the port entirely.

3. **CRITICAL — Multiple HID Interfaces**: Device may expose multiple interfaces. Must enumerate ALL and log `usage_page`, `usage`, `interface_number` to find the correct one.

4. **CRITICAL — Buffer Sizes**: Feature Reports need 33 bytes (32 + 1 for report ID). RGB writes need 1024 bytes. Off-by-one is a classic failure mode.

5. **Device Seizure**: HIDAPI on macOS seizes device exclusively. If iCUE or any other process has it open, `hid.open()` will fail.

6. **Temperature Encoding**: `int16` Little-Endian at bytes[2:4], divided by 10.0. Must use `struct.unpack('<h', ...)` — signed, little-endian.

---

## Work Objectives

### Core Objective
Prove that the Corsair XC7 RGB ELITE LCD water block can be controlled via USB HID on macOS (Hackintosh), validating that the protocol reverse-engineered from OpenLinkHub works cross-platform.

### Concrete Deliverables
- `verify_xc7.py` — single Python file, ≤150 lines, zero external deps beyond `hidapi`
- Terminal output with diagnostic info at each step
- Pass/fail verdict for each of: USB detection, HID enumerate/open, temperature read, RGB write

### Definition of Done
- [ ] `python3 verify_xc7.py` runs to completion without unhandled exceptions
- [ ] Script prints device info (manufacturer, product, serial) from HID
- [ ] Script prints a temperature value in Celsius (plausible range 15-50°C)
- [ ] Script sends solid red to all 31 LEDs; user visually confirms LEDs changed
- [ ] Script exits with code 0 (all pass) or non-zero (step number that failed)

### Must Have
- Step 0: Hardware-level USB bus check via `system_profiler`
- Step 1: HID enumerate + open with full diagnostic output
- Step 2: Temperature read via Feature Report 0x18
- Step 3: RGB write via Output Report (1024-byte buffer, [0x02, 0x07, 0x1F, ...])
- Clear error messages with suggested fixes for each failure mode

### Must NOT Have (Guardrails)
- ❌ No LCD commands (no 0x03 feature reports, no transferTypeLcd)
- ❌ No animation loops, breathing effects, or continuous monitoring
- ❌ No class hierarchy, abstraction layers, or "device driver" architecture
- ❌ No command-line argument parsing, config files, or logging frameworks
- ❌ No Go compilation, Xcode project, or anything requiring a build step
- ❌ No error recovery/retry logic — fail fast with clear diagnostics
- ❌ No multi-device support — hardcode VID/PID, use first match
- ❌ No daemon/service behavior — run once, print results, exit

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** for all criteria EXCEPT Step 3b (visual LED check — irreducible for hardware).

### Test Decision
- **Infrastructure exists**: NO (greenfield project)
- **Automated tests**: NO (this IS the test — it's a verification script)
- **Framework**: None needed

### QA Policy
Every task includes agent-executed QA scenarios. Evidence saved to `.sisyphus/evidence/`.

- **CLI verification**: Use Bash — run script, capture stdout/stderr, check exit code
- **Hardware verification**: ONE irreducible human check — "Are LEDs red?"

---

## Execution Strategy

### Sequential Execution (NOT Parallel)

> This plan is intentionally sequential. Each task depends on the previous. Running them in parallel is impossible because:
> - Task 2 needs the pip package from Task 1
> - Task 3 needs the script from Task 2
> - Task 3 cannot run if Task 2's hardware check fails

```
Task 1: Environment setup + hardware pre-check [quick]
  ↓
Task 2: Write verify_xc7.py [deep]
  ↓
Task 3: Execute verification + capture results [quick]
```

### Dependency Matrix

| Task | Depends On | Blocks | Wave |
|------|-----------|--------|------|
| 1    | —         | 2, 3   | 1    |
| 2    | 1         | 3      | 2    |
| 3    | 2         | F1-F2  | 3    |
| F1   | 3         | —      | FINAL|
| F2   | 3         | —      | FINAL|

### Agent Dispatch Summary

- **Wave 1**: 1 task — T1 → `quick`
- **Wave 2**: 1 task — T2 → `deep`
- **Wave 3**: 1 task — T3 → `quick`
- **FINAL**: 2 tasks — F1 → `deep`, F2 → `quick`

---

## TODOs

- [x] 1. Environment Setup + Hardware Pre-Check

  **What to do**:
  - Verify Python 3 is available: `python3 --version` (expect 3.9+)
  - Install hidapi: `pip3 install hidapi`
  - Verify hidapi installed: `python3 -c "import hid; print(hid.enumerate())"` (should print a list, possibly empty)
  - Run hardware detection: `system_profiler SPUSBDataType 2>/dev/null | grep -B5 -A10 -i "1b1c"`
  - If no results from system_profiler, also try: `ioreg -p IOUSB -l | grep -B5 -A10 -i "1b1c"`
  - Record the FULL output — this tells us if the device is even on the USB bus
  - If device NOT found: STOP. The problem is hardware/USB mapping, not software. Document this finding and exit the plan early.
  - If device IS found: record the exact USB path, interfaces, and any descriptors shown

  **Must NOT do**:
  - Do NOT attempt to open any HID device in this task
  - Do NOT install Go, Swift, or any other language tooling
  - Do NOT install libusb separately (hidapi bundles its own)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple shell commands, no code writing
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 1 (solo)
  - **Blocks**: [Task 2, Task 3]
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `OpenLinkHub/99-openlinkhub.rules` line 16 — Confirms VID `1b1c`, PID `0c42` is the XC7 ELITE LCD

  **External References**:
  - Apple `system_profiler` docs — SPUSBDataType lists all USB devices with VID/PID
  - Python hidapi: `pip install hidapi` — provides the `hid` module for HID access on macOS via IOKit

  **WHY Each Reference Matters**:
  - The udev rules file confirms the exact VID:PID we're looking for
  - system_profiler is the canonical macOS tool to verify USB device visibility before any software access attempt

  **Acceptance Criteria**:

  - [ ] `python3 --version` outputs 3.9 or higher
  - [ ] `python3 -c "import hid"` exits with code 0
  - [ ] `system_profiler SPUSBDataType` output is captured to `.sisyphus/evidence/task-1-usb-detection.txt`

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Python hidapi package is importable
    Tool: Bash
    Preconditions: pip3 install hidapi has been run
    Steps:
      1. Run: python3 -c "import hid; devs = hid.enumerate(0x1b1c, 0x0c42); print(f'Found {len(devs)} XC7 device(s)'); [print(f'  path={d[\"path\"]}, usage_page=0x{d[\"usage_page\"]:04x}, usage=0x{d[\"usage\"]:04x}, interface={d[\"interface_number\"]}') for d in devs]"
      2. Capture output to .sisyphus/evidence/task-1-hid-enumerate.txt
    Expected Result: Script runs without ImportError. May find 0 or more devices.
    Failure Indicators: ImportError on `import hid`, or pip install failure
    Evidence: .sisyphus/evidence/task-1-hid-enumerate.txt

  Scenario: USB device visibility on bus
    Tool: Bash
    Preconditions: XC7 water block physically connected via USB
    Steps:
      1. Run: system_profiler SPUSBDataType 2>/dev/null | grep -B5 -A15 -i "0c42"
      2. If empty, run: system_profiler SPUSBDataType 2>/dev/null | grep -B5 -A15 -i "1b1c"
      3. If still empty, run: ioreg -p IOUSB -l | grep -i "1b1c"
      4. Capture ALL output to .sisyphus/evidence/task-1-usb-detection.txt
    Expected Result: At least one command shows VID 0x1b1c. Ideally PID 0x0c42 visible.
    Failure Indicators: No output from any command → device not on USB bus → likely USB port not mapped in Hackintosh config
    Evidence: .sisyphus/evidence/task-1-usb-detection.txt
  ```

  **Evidence to Capture:**
  - [ ] task-1-usb-detection.txt — full system_profiler/ioreg output
  - [ ] task-1-hid-enumerate.txt — Python hid.enumerate() output

  **Commit**: NO (no source code yet)

---

- [x] 2. Write `verify_xc7.py` — XC7 HID Protocol Verification Script

  **What to do**:
  Write a single Python script (`verify_xc7.py` in project root) that performs 4 sequential verification steps. The script must be ≤150 lines, use only stdlib + `hid` module, and follow the exact protocol from OpenLinkHub's xc7.go.

  **Step 0 — USB Bus Detection:**
  - Shell out to `subprocess.run(['system_profiler', 'SPUSBDataType'], capture_output=True, text=True)`
  - Search stdout for `0x0c42` (case-insensitive)
  - Print: `[Step 0] USB Detection: FOUND` or `FAIL — device not on USB bus`
  - If FAIL: print suggestion "Check Hackintosh USB mapping (USBMap/USBToolBox). The XC7's internal USB header port may not be included."
  - If FAIL: `sys.exit(1)`

  **Step 1 — HID Enumerate & Open:**
  - Call `hid.enumerate(0x1b1c, 0x0c42)`
  - For EACH device found, print: `path`, `manufacturer_string`, `product_string`, `serial_number`, `usage_page` (hex), `usage` (hex), `interface_number`
  - If zero devices: print "FAIL — device on USB bus but HID enumerate found nothing. Check: (1) Is iCUE or another app holding the device? (2) macOS Input Monitoring permissions?"
  - If FAIL: `sys.exit(2)`
  - Open the FIRST device: `device = hid.Device(path=devices[0]['path'])`
  - If open fails: catch exception, print "FAIL — could not open device. Another process may have it seized. Close iCUE or other Corsair software."
  - If FAIL: `sys.exit(2)`
  - Print: `[Step 1] HID Device: OPENED — {manufacturer} {product} (serial: {serial})`

  **Step 2 — Temperature Read (Feature Report):**
  - Read Feature Report: `buf = device.get_feature_report(0x18, 33)`
  - Print raw bytes: `[Step 2] Raw: {buf[:8].hex()}`
  - Decode temperature: `temp = struct.unpack('<h', bytes(buf[2:4]))[0] / 10.0`
  - Print: `[Step 2] Temperature: {temp:.1f}°C`
  - Sanity check: if temp < -10 or temp > 80, print warning but do NOT fail (sensor may be in unusual state)
  - If exception: `sys.exit(3)`

  **Step 3 — RGB Write (Output Report):**
  - Build 1024-byte buffer:
    ```python
    buf = bytearray(1024)
    buf[0] = 0x02          # Report type
    buf[1] = 0x07          # RGB Data command
    buf[2] = 0x1F          # 31 LED channels
    for i in range(31):
        buf[3 + i*3] = 0xFF  # Red
        buf[4 + i*3] = 0x00  # Green
        buf[5 + i*3] = 0x00  # Blue
    ```
  - Write: `bytes_written = device.write(buf)`
  - Print: `[Step 3] RGB Write: {bytes_written} bytes sent`
  - Print: `[Step 3] Buffer head: {buf[:16].hex()}`
  - Print: `[Step 3] CHECK: Look at the XC7 water block. Are all LEDs red? (This is the only manual check)`
  - If write throws exception: `sys.exit(4)`

  **Final output:**
  - Print: `\n=== VERIFICATION COMPLETE ===`
  - Print: `All 4 steps passed. The XC7 HID protocol works on this macOS system.`
  - Print: `Next: Build full control tool with RGB effects, temperature monitoring, and launchd auto-start.`
  - `sys.exit(0)`

  **Also create `requirements.txt`:**
  ```
  hidapi
  ```

  **Must NOT do**:
  - Do NOT add argparse, click, or any CLI framework
  - Do NOT create classes, modules, or packages
  - Do NOT add animation loops or breathing effects
  - Do NOT send LCD commands (no 0x03 feature reports)
  - Do NOT implement retry/recovery logic — fail fast
  - Do NOT add `try/except` that silently swallows errors — always print the exception
  - Do NOT use `struct.unpack('>h', ...)` (big-endian) — MUST use `'<h'` (little-endian)
  - Do NOT use `struct.unpack('<H', ...)` (unsigned) — MUST use `'<h'` (signed)
  - Do NOT use `device.send_feature_report()` for RGB — RGB uses `device.write()`
  - Do NOT use `device.write()` for temperature — temperature uses `device.get_feature_report()`

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Protocol-sensitive code with exact byte layouts. One wrong byte = silent failure. Needs careful implementation.
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser work
    - `frontend-ui-ux`: No UI

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 2 (solo)
  - **Blocks**: [Task 3]
  - **Blocked By**: [Task 1] — needs hidapi installed and hardware pre-check passed

  **References (CRITICAL — Be Exhaustive):**

  **Pattern References** (existing code to follow):
  - `OpenLinkHub/src/devices/xc7/xc7.go` lines 680-690 (`getTemperatureProbeData`) — Temperature read implementation. Uses `GetFeatureReport(buf)` where `buf[0] = 0x18`, buffer size 33. Temperature at bytes[2:4] as int16 LE / 10.0.
  - `OpenLinkHub/src/devices/xc7/xc7.go` lines 1596-1611 (`transfer`, RGB path) — RGB write implementation. Uses `dev.Write(bufferW)` where `bufferW[0]=0x02, bufferW[1]=0x07, bufferW[2]=LEDChannels(31)`. Buffer size 1024. Color data starts at byte 3, format: 31 × (R, G, B).
  - `OpenLinkHub/src/devices/xc7/xc7.go` lines 146-150 — Protocol constants: `temperatureReportId=24`, `firmwareReportId=5`, `featureReportSize=32`, `lcdBufferSize=1024`, `lcdHeaderSize=8`.
  - `OpenLinkHub/src/devices/xc7/xc7.go` line 172 — Product ID check: `if productId == 3138` (decimal of 0x0C42) → HasLCD=true, LEDChannels=31.

  **API/Type References:**
  - Python `hid` module API: `hid.enumerate(vid, pid)` returns list of dicts with keys: `path`, `vendor_id`, `product_id`, `serial_number`, `manufacturer_string`, `product_string`, `usage_page`, `usage`, `interface_number`
  - `hid.Device(path=...)` or `hid.Device(vid=, pid=)` opens device exclusively
  - `device.get_feature_report(report_id, max_length)` — report_id is FIRST ARG, NOT in buffer
  - `device.write(data)` — data[0] IS the report ID (0x02 for RGB)
  - `device.send_feature_report(data)` — data[0] IS the report ID
  - `device.close()` — release exclusive access

  **External References:**
  - OpenLinkHub xc7.go: https://github.com/jurkovic-nikola/OpenLinkHub/blob/main/src/devices/xc7/xc7.go
  - Python hidapi docs: https://pypi.org/project/hidapi/
  - HIDAPI C library: https://github.com/libusb/hidapi
  - OpenLinkHub supported devices: https://openlinkhub.dev/devices.html (confirms PID 0c42 = XC7 ELITE LCD)

  **WHY Each Reference Matters:**
  - The xc7.go `getTemperatureProbeData` is the EXACT function we're reimplementing in Python for Step 2
  - The xc7.go `transfer` function RGB path is the EXACT operation for Step 3
  - The Python `hid` API has ASYMMETRIC behavior: `get_feature_report` takes report_id as arg, but `write` expects it as `data[0]`. Getting this wrong = silent failure or wrong data.
  - The OpenLinkHub supported devices page is the authoritative source confirming our VID:PID mapping

  **Acceptance Criteria:**

  - [ ] `verify_xc7.py` exists in project root
  - [ ] `requirements.txt` exists with single line `hidapi`
  - [ ] `wc -l verify_xc7.py` outputs ≤ 150
  - [ ] `python3 -c "import ast; ast.parse(open('verify_xc7.py').read())"` exits 0 (valid Python)
  - [ ] Script contains `0x1b1c` and `0x0c42` (hardcoded VID/PID)
  - [ ] Script contains `struct.unpack('<h'` (signed little-endian int16)
  - [ ] Script contains `bytearray(1024)` (correct RGB buffer size)
  - [ ] Script contains `buf[0] = 0x02` and `buf[1] = 0x07` and `buf[2] = 0x1f` (RGB header)
  - [ ] Script contains `get_feature_report(0x18` (temperature read)
  - [ ] Script contains `device.write(` (RGB output report, NOT send_feature_report)
  - [ ] Script does NOT contain `argparse` or `click`
  - [ ] Script does NOT contain `class `

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Script is syntactically valid and passes static checks
    Tool: Bash
    Preconditions: verify_xc7.py exists
    Steps:
      1. Run: python3 -c "import ast; ast.parse(open('verify_xc7.py').read()); print('SYNTAX OK')"
      2. Run: wc -l verify_xc7.py
      3. Run: grep -c 'class ' verify_xc7.py (expect 0)
      4. Run: grep -c 'argparse\|click' verify_xc7.py (expect 0)
      5. Run: grep -c "struct.unpack('<h'" verify_xc7.py (expect ≥1)
      6. Run: grep -c 'get_feature_report(0x18' verify_xc7.py (expect ≥1)
      7. Run: grep -c '\.write(' verify_xc7.py (expect ≥1)
    Expected Result: All checks pass, line count ≤ 150
    Failure Indicators: Syntax error, line count > 150, missing protocol constants
    Evidence: .sisyphus/evidence/task-2-static-check.txt

  Scenario: Protocol constants match OpenLinkHub reference
    Tool: Bash
    Preconditions: verify_xc7.py exists
    Steps:
      1. Run: grep -n '0x1b1c\|0x0c42\|0x18\|0x02.*0x07\|0x1f\|1024\|bytearray' verify_xc7.py
      2. Verify output contains all expected constants
    Expected Result: All protocol constants present in script
    Failure Indicators: Missing VID/PID, wrong report IDs, wrong buffer size
    Evidence: .sisyphus/evidence/task-2-constants-check.txt
  ```

  **Evidence to Capture:**
  - [ ] task-2-static-check.txt — syntax and static analysis results
  - [ ] task-2-constants-check.txt — protocol constant verification

  **Commit**: YES
  - Message: `feat(verify): add XC7 HID protocol verification script`
  - Files: `verify_xc7.py`, `requirements.txt`
  - Pre-commit: `python3 -c "import ast; ast.parse(open('verify_xc7.py').read())"`

---

- [x] 3. Execute Verification Script + Capture Results

  **What to do**:
  - Ensure no other Corsair software is running: `ps aux | grep -i corsair` (kill if found)
  - Run the verification script: `python3 verify_xc7.py 2>&1 | tee .sisyphus/evidence/task-3-verify-run.txt`
  - Capture the exit code: `echo "Exit code: $?" >> .sisyphus/evidence/task-3-verify-run.txt`
  - Read the output carefully and interpret each step's result
  - If Step 0 fails (device not on USB): document this as "BLOCKED — USB port not mapped". This is a Hackintosh configuration issue, not a software issue. Suggested fix: use USBToolBox or USBMap to include the XC7's USB port.
  - If Step 1 fails (enumerate empty): document "HID not accessible". Possible causes: (a) device seized by another process, (b) macOS TCC Input Monitoring blocking access, (c) wrong interface.
  - If Step 2 fails (temperature read error): document the exact error. May need to try a different HID interface from the enumerate list.
  - If Step 3 fails (RGB write error): document the exact error. May indicate wrong buffer format or wrong interface.
  - If ALL steps pass: document success. Ask user to confirm LED color change visually.

  **Must NOT do**:
  - Do NOT modify verify_xc7.py during this task — run it as-is
  - Do NOT install additional software
  - Do NOT attempt to "fix" failures by changing the script — just document them

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Running a script and capturing output, no code changes
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (solo)
  - **Blocks**: [F1, F2]
  - **Blocked By**: [Task 2] — needs verify_xc7.py to exist

  **References:**

  **Pattern References:**
  - Task 2 output — the verify_xc7.py script that was written
  - `.sisyphus/evidence/task-1-usb-detection.txt` — pre-check results from Task 1 to compare against

  **WHY Each Reference Matters:**
  - Task 1's USB detection tells us whether to even expect the script to succeed
  - If Task 1 found the device but the script fails, the problem is software (permissions, interface selection)
  - If Task 1 did NOT find the device, the script will definitely fail at Step 0

  **Acceptance Criteria:**

  - [ ] `.sisyphus/evidence/task-3-verify-run.txt` exists and is non-empty
  - [ ] File contains output from all attempted steps
  - [ ] Exit code is recorded in the file
  - [ ] If exit code is 0: all 4 steps show PASS/success indicators
  - [ ] If exit code is non-zero: failure is clearly documented with step number and error message

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Happy path — all verification steps pass
    Tool: Bash
    Preconditions: verify_xc7.py exists, hidapi installed, XC7 connected and visible on USB bus
    Steps:
      1. Run: ps aux | grep -i corsair | grep -v grep (should be empty — no Corsair software running)
      2. Run: python3 verify_xc7.py 2>&1 | tee .sisyphus/evidence/task-3-verify-run.txt
      3. Check exit code: echo $?
      4. Inspect output: grep '\[Step' .sisyphus/evidence/task-3-verify-run.txt
    Expected Result: Exit code 0. Output contains [Step 0] FOUND, [Step 1] OPENED, [Step 2] Temperature: XX.X°C, [Step 3] RGB Write: 1024 bytes
    Failure Indicators: Non-zero exit code, missing step output, exception traceback
    Evidence: .sisyphus/evidence/task-3-verify-run.txt

  Scenario: Failure path — device not on USB bus
    Tool: Bash
    Preconditions: XC7 may not be properly mapped in Hackintosh USB config
    Steps:
      1. Run: python3 verify_xc7.py 2>&1 | tee .sisyphus/evidence/task-3-verify-run.txt
      2. Check output for Step 0 FAIL message
      3. Verify exit code is 1
    Expected Result: Script exits at Step 0 with clear error about USB mapping
    Failure Indicators: Script hangs, crashes without message, or exits with wrong code
    Evidence: .sisyphus/evidence/task-3-verify-run.txt
  ```

  **Evidence to Capture:**
  - [ ] task-3-verify-run.txt — full script output including exit code

  **Commit**: YES
  - Message: `docs(verify): capture XC7 HID verification results`
  - Files: `.sisyphus/evidence/task-3-verify-run.txt`
  - Pre-commit: none

---

## Final Verification Wave

> 2 review agents run in PARALLEL. Both must APPROVE.

- [x] F1. **Verification Results Audit** — `deep`
  Read the script output captured in `.sisyphus/evidence/task-3-verify-run.txt`. For each step (0-3): confirm the output matches expected success criteria. Check: (a) Step 0 found device on USB bus, (b) Step 1 printed device info with Corsair manufacturer, (c) Step 2 printed temperature in plausible range, (d) Step 3 printed "1024 bytes sent" without error. If ANY step failed, analyze the error output, identify the root cause, and document a specific fix. Do NOT re-run the script — analyze existing output only.
  Output: `Step 0 [PASS/FAIL] | Step 1 [PASS/FAIL] | Step 2 [PASS/FAIL] | Step 3 [PASS/FAIL] | VERDICT: APPROVE/REJECT`

- [x] F2. **Script Quality Check** — `quick`
  Read `verify_xc7.py`. Verify: (a) ≤150 lines, (b) no imports beyond `hid`, `struct`, `subprocess`, `sys`, `time`, (c) no class definitions, (d) no argparse/config, (e) hardcoded VID=0x1B1C PID=0x0C42, (f) RGB buffer is exactly 1024 bytes starting with [0x02, 0x07, 0x1F], (g) temperature uses `struct.unpack('<h', ...)` not `'>h'` or `'H'`, (h) exit code reflects step that failed. If any guardrail is violated, list the specific line(s).
  Output: `Lines [N] | Imports [OK/VIOLATION] | Guardrails [N/8 pass] | VERDICT: APPROVE/REJECT`

---

## Commit Strategy

- **After Task 2**: `feat(verify): add XC7 HID protocol verification script` — verify_xc7.py, requirements.txt
- **After Task 3**: `docs(verify): capture XC7 verification results` — .sisyphus/evidence/*

---

## Success Criteria

### Verification Commands
```bash
python3 verify_xc7.py       # Expected: Steps 0-3 all PASS, exit code 0
wc -l verify_xc7.py         # Expected: ≤ 150
pip3 show hidapi             # Expected: package info shown
```

### Final Checklist
- [ ] Device detected on USB bus
- [ ] HID device opened successfully
- [ ] Temperature read returns plausible Celsius value
- [ ] RGB write sends 1024 bytes without error
- [ ] User visually confirms LEDs changed to red
- [ ] Script is single file, ≤150 lines, no build step required
