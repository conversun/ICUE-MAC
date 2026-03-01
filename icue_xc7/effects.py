"""RGB effects for the Corsair XC7 water block."""

import colorsys
import math
import time

from icue_xc7.device import XC7Device, LED_COUNT


def effect_off(dev: XC7Device, keep: bool = False):
    """Turn off all LEDs.
    
    Args:
        dev: XC7Device instance
        keep: If True, loop and resend off command every 2 seconds (Ctrl+C to stop)
    """
    if keep:
        print("LEDs off (keep-alive). Ctrl+C to stop.")
        while True:
            dev.set_all_rgb(0, 0, 0)
            time.sleep(2.0)
    else:
        dev.set_all_rgb(0, 0, 0)


def effect_static(dev: XC7Device, r: int, g: int, b: int, keep: bool = False):
    """Set all LEDs to a static color.
    
    Args:
        dev: XC7Device instance
        r, g, b: RGB values (0-255)
        keep: If True, loop and resend color every 2 seconds (Ctrl+C to stop)
    """
    if keep:
        print(f"Static RGB({r},{g},{b}) (keep-alive). Ctrl+C to stop.")
        while True:
            dev.set_all_rgb(r, g, b)
            time.sleep(2.0)
    else:
        dev.set_all_rgb(r, g, b)


def show_info(dev: XC7Device):
    """Print device info and water temperature."""
    temp = dev.get_temperature()
    print(f"Device:  Corsair XC7 RGB ELITE LCD")
    print(f"LEDs:    {LED_COUNT}")
    print(f"Water T: {temp:.1f}\u00b0C")


def effect_rainbow(dev: XC7Device, speed: float = 1.0):
    """Rainbow cycle across all LEDs. Ctrl+C to stop."""
    offset = 0.0
    while True:
        colors = []
        for i in range(LED_COUNT):
            hue = ((i / LED_COUNT) + offset) % 1.0
            r, g, b = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
            colors.append((int(r * 255), int(g * 255), int(b * 255)))
        dev.set_rgb(colors)
        offset = (offset + 0.01 * speed) % 1.0
        time.sleep(0.03)


def effect_breathe(dev: XC7Device, r: int, g: int, b: int, speed: float = 1.0):
    """Breathing pulse effect. Ctrl+C to stop."""
    t = 0.0
    while True:
        brightness = (math.sin(t) + 1.0) / 2.0  # 0.0 to 1.0
        dev.set_all_rgb(
            int(r * brightness),
            int(g * brightness),
            int(b * brightness),
        )
        t += 0.05 * speed
        time.sleep(0.03)


def temp_to_color(temp: float) -> tuple[int, int, int]:
    """Map temperature to RGB: blue(cold) -> green(warm) -> red(hot)."""
    if temp <= 25:
        return (0, 0, 255)
    elif temp <= 35:
        t = (temp - 25) / 10.0
        return (0, int(255 * t), int(255 * (1 - t)))  # blue -> green
    elif temp <= 45:
        t = (temp - 35) / 10.0
        return (int(255 * t), int(255 * (1 - t)), 0)  # green -> red
    else:
        return (255, 0, 0)


def effect_temp(dev: XC7Device, once: bool = False):
    """Set LED color based on water temperature. Ctrl+C to stop."""
    while True:
        temp = dev.get_temperature()
        r, g, b = temp_to_color(temp)
        dev.set_all_rgb(r, g, b)
        print(f"\rTemp: {temp:.1f}\u00b0C \u2192 RGB({r},{g},{b})", end="", flush=True)
        if once:
            print()
            break
        time.sleep(2.0)
