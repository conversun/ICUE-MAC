"""HID communication module for Corsair XC7 RGB ELITE LCD."""

import hid
import struct

VID = 0x1B1C
PID = 0x0C42
LED_COUNT = 31


class XC7Device:
    """Wrapper around hidapi for the XC7 water block."""

    def __init__(self):
        self._dev = None

    def open(self):
        """Open the HID device. Raises RuntimeError if not found."""
        devices = hid.enumerate(VID, PID)
        if not devices:
            raise RuntimeError(
                "XC7 not found. Check USB connection and ensure no other "
                "application (e.g. OpenLinkHub) has the device open."
            )
        self._dev = hid.device()
        self._dev.open_path(devices[0]["path"])

    def close(self):
        """Close the HID device."""
        if self._dev:
            self._dev.close()
            self._dev = None

    def set_rgb(self, colors: list[tuple[int, int, int]]):
        """Set RGB for all LEDs.

        Args:
            colors: List of (R, G, B) tuples, length <= 31.
        """
        buf = bytearray(1024)
        buf[0] = 0x02  # report ID
        buf[1] = 0x07  # RGB command
        buf[2] = 0x1F  # LED count (31)
        for i, (r, g, b) in enumerate(colors[:LED_COUNT]):
            buf[3 + i * 3] = r
            buf[4 + i * 3] = g
            buf[5 + i * 3] = b
        self._dev.write(buf)

    def set_all_rgb(self, r: int, g: int, b: int):
        """Set all LEDs to the same color."""
        self.set_rgb([(r, g, b)] * LED_COUNT)

    def get_temperature(self) -> float:
        """Read water temperature in Celsius."""
        buf = self._dev.get_feature_report(0x18, 33)
        return struct.unpack("<h", bytes(buf[2:4]))[0] / 10.0

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, *args):
        self.close()
