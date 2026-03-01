# XC7 HID Verification - Learnings

## Task 1: Environment Setup + Hardware Pre-Check

### Key Findings

1. **Python Environment Management**
   - System Python (3.12.12) is managed by `uv` (Astral's Python package manager)
   - Cannot use `pip install` directly due to PEP 668 externally-managed environment
   - Solution: Create virtual environment with `python3 -m venv .venv`
   - Virtual environment works seamlessly with hidapi

2. **hidapi Installation**
   - Version: 0.15.0 (latest stable)
   - Installs cleanly in virtual environment
   - No additional dependencies required (libusb bundled)
   - Import: `import hid` works immediately after installation

3. **Device Detection - Two-Layer Verification**
   - **Layer 1 (USB Bus)**: `system_profiler SPUSBDataType`
     - Shows device at OS level
     - Confirms physical connectivity
     - Provides Location ID, power requirements, serial number
   - **Layer 2 (HID Subsystem)**: `hid.enumerate(0x1b1c, 0x0c42)`
     - Shows device at HID API level
     - Confirms IOKit driver binding
     - Provides interface number, usage page, usage code

4. **XC7 Device Characteristics**
   - VID: 0x1b1c (CORSAIR MEMORY INC.)
   - PID: 0x0c42 (XC7 ELITE LCD)
   - Serial: 2329079710067 (this unit)
   - USB Location: 0x14d00000 / 3
   - Power: 500 mA required
   - HID Interface: 0
   - Usage Page: 0x000c (Consumer)
   - Usage: 0x0001 (Consumer Control)

5. **Hackintosh USB Mapping**
   - Device is properly mapped in this Hackintosh's USB configuration
   - No USB mapping issues detected
   - Device visible at both USB bus and HID subsystem levels
   - Ready for HID communication

### Protocol Insights

- Device uses mixed HID operations:
  - **Feature Reports** for reads (e.g., temperature via 0x18)
  - **Output Reports** for writes (e.g., RGB via 0x02/0x07)
- No initialization handshake required
- Device can be opened immediately after enumeration

### Verification Strategy

The two-layer verification approach is robust:
1. If device not on USB bus → hardware/Hackintosh USB mapping issue
2. If on USB bus but not enumerable → permissions/driver issue
3. If enumerable but can't open → device seized by another process
4. If open but read/write fails → protocol/buffer format issue

This task confirmed layers 1-3 are working correctly.

### Next Task Preparation

Task 2 will implement the protocol operations:
- Step 0: Replicate USB bus check in Python (subprocess.run system_profiler)
- Step 1: Use hid.enumerate() and hid.Device() to open
- Step 2: Read Feature Report 0x18 for temperature (33-byte buffer, int16 LE at bytes[2:4])
- Step 3: Write Output Report with RGB data (1024-byte buffer, [0x02, 0x07, 0x1F, ...])

All prerequisites are met.

## Task 2: Verification Script Implementation

### Implementation Learnings

1. **Protocol-Exact Ordering Matters**
   - The script should fail fast in strict sequence: USB bus visibility -> HID enumerate/open -> feature report read -> output report write.
   - Early exits with step-specific codes make hardware troubleshooting unambiguous.

2. **XC7 Temperature Read Mapping Confirmed**
   - `device.get_feature_report(0x18, 33)` returns the expected feature payload shape.
   - Temperature decode path remains `struct.unpack('<h', bytes(buf[2:4]))[0] / 10.0`.

3. **XC7 RGB Write Mapping Confirmed**
   - RGB write path uses `device.write(bytearray(1024))` with header bytes `[0x02, 0x07, 0x1f]`.
   - 31 channels map as contiguous RGB triplets beginning at byte offset 3.

4. **Static Guardrails Satisfied**
   - Script length is 106 lines (under 150-line limit).
   - No argparse/click/class usage; script remains single-file procedural verification.
   - `requirements.txt` contains only `hidapi`.

5. **LSP Environment Note**
   - basedpyright LSP was not initially available on PATH; installed and exposed `basedpyright-langserver` so diagnostics can run for Python files.
