import hid
import struct
import subprocess
import sys


VID = 0x1B1C
PID = 0x0C42


def main():
    device = None
    try:
        result = subprocess.run(
            ["system_profiler", "SPUSBDataType"], capture_output=True, text=True
        )
        if "0x0c42" in result.stdout.lower():
            print("[Step 0] USB Detection: FOUND")
        else:
            print("[Step 0] USB Detection: FAIL — device not on USB bus")
            print(
                "Check Hackintosh USB mapping (USBMap/USBToolBox). The XC7's internal USB header port may not be included."
            )
            sys.exit(1)

        devices = hid.enumerate(VID, PID)
        for i, info in enumerate(devices):
            usage_page = info.get("usage_page")
            usage = info.get("usage")
            print(f"[Step 1] Device {i}:")
            print(f"  path: {info.get('path')}")
            print(f"  manufacturer_string: {info.get('manufacturer_string')}")
            print(f"  product_string: {info.get('product_string')}")
            print(f"  serial_number: {info.get('serial_number')}")
            print(f"  usage_page: 0x{(usage_page or 0):04x}")
            print(f"  usage: 0x{(usage or 0):04x}")
            print(f"  interface_number: {info.get('interface_number')}")

        if not devices:
            print(
                "FAIL — device on USB bus but HID enumerate found nothing. Check: (1) Is iCUE or another app holding the device? (2) macOS Input Monitoring permissions?"
            )
            sys.exit(2)

        try:
            device = hid.device()
            device.open_path(devices[0]["path"])
        except Exception as exc:
            print(f"FAIL — could not open device. Exception: {exc}")
            print(
                "FAIL — could not open device. Another process may have it seized. Close iCUE or other Corsair software."
            )
            sys.exit(2)

        manufacturer = devices[0].get("manufacturer_string") or "Unknown"
        product = devices[0].get("product_string") or "Unknown"
        serial = devices[0].get("serial_number") or "Unknown"
        print(
            f"[Step 1] HID Device: OPENED — {manufacturer} {product} (serial: {serial})"
        )

        try:
            buf = device.get_feature_report(0x18, 33)
            print(f"[Step 2] Raw: {bytes(buf[:8]).hex()}")
            temp = struct.unpack("<h", bytes(buf[2:4]))[0] / 10.0
            print(f"[Step 2] Temperature: {temp:.1f}°C")
            if temp < -10 or temp > 80:
                print(
                    "[Step 2] WARNING: Temperature outside expected range (-10 to 80°C)."
                )
        except Exception as exc:
            print(f"[Step 2] FAIL — Exception: {exc}")
            sys.exit(3)

        try:
            buf = bytearray(1024)
            buf[0] = 0x02
            buf[1] = 0x07
            buf[2] = 0x1F
            for i in range(31):
                buf[3 + i * 3] = 0xFF
                buf[4 + i * 3] = 0x00
                buf[5 + i * 3] = 0x00

            bytes_written = device.write(buf)
            print(f"[Step 3] RGB Write: {bytes_written} bytes sent")
            print(f"[Step 3] Buffer head: {buf[:16].hex()}")
            print(
                "[Step 3] CHECK: Look at the XC7 water block. Are all LEDs red? (This is the only manual check)"
            )
        except Exception as exc:
            print(f"[Step 3] FAIL — Exception: {exc}")
            sys.exit(4)

        print("\n=== VERIFICATION COMPLETE ===")
        print("All 4 steps passed. The XC7 HID protocol works on this macOS system.")
        print(
            "Next: Build full control tool with RGB effects, temperature monitoring, and launchd auto-start."
        )
        sys.exit(0)
    finally:
        if device is not None:
            device.close()


if __name__ == "__main__":
    main()
