"""CLI entry point for icue-xc7."""

import argparse
import signal
import sys

from icue_xc7.device import XC7Device
from icue_xc7 import effects


def parse_color(raw: list[str]) -> tuple[int, int, int]:
    """Parse color from hex string or R G B integers.

    Supports:
        ["FF0000"]      -> (255, 0, 0)
        ["255", "0", "0"] -> (255, 0, 0)
    """
    if len(raw) == 1:
        hex_str = raw[0].lstrip("#")
        if len(hex_str) != 6:
            raise ValueError(
                f"Invalid hex color: {raw[0]}. Use 6-digit hex like FF0000."
            )
        r = int(hex_str[0:2], 16)
        g = int(hex_str[2:4], 16)
        b = int(hex_str[4:6], 16)
        return (r, g, b)
    elif len(raw) == 3:
        r, g, b = int(raw[0]), int(raw[1]), int(raw[2])
        if not all(0 <= v <= 255 for v in (r, g, b)):
            raise ValueError("RGB values must be 0-255.")
        return (r, g, b)
    else:
        raise ValueError(
            "Color must be a hex string (FF0000) or three integers (255 0 0)."
        )


def main():
    parser = argparse.ArgumentParser(
        prog="icue-xc7",
        description="Corsair XC7 RGB ELITE LCD — macOS RGB Control",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_off = sub.add_parser("off", help="Turn off all LEDs")
    p_off.add_argument(
        "--keep", action="store_true", help="Keep-alive mode: resend off command every 2 seconds (Ctrl+C to stop)"
    )
    sub.add_parser("info", help="Show device info + temperature")

    p_static = sub.add_parser("static", help="Set static color")
    p_static.add_argument(
        "color",
        nargs="+",
        help="Hex color (FF0000) or R G B (255 0 0)",
    )
    p_static.add_argument(
        "--keep", action="store_true", help="Keep-alive mode: resend color every 2 seconds (Ctrl+C to stop)"
    )

    p_rainbow = sub.add_parser("rainbow", help="Rainbow cycle (Ctrl+C to stop)")
    p_rainbow.add_argument(
        "--speed", type=float, default=1.0, help="Animation speed multiplier"
    )

    p_breathe = sub.add_parser("breathe", help="Breathing effect (Ctrl+C to stop)")
    p_breathe.add_argument(
        "color",
        nargs="+",
        help="Hex color (FF0000) or R G B (255 0 0)",
    )
    p_breathe.add_argument(
        "--speed", type=float, default=1.0, help="Animation speed multiplier"
    )

    p_temp = sub.add_parser("temp", help="Temperature-based color (Ctrl+C to stop)")
    p_temp.add_argument("--once", action="store_true", help="Set color once and exit")

    args = parser.parse_args()

    # Graceful exit on Ctrl+C — the context manager will close the device
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))

    try:
        with XC7Device() as dev:
            if args.command == "off":
                effects.effect_off(dev, keep=args.keep)
                if not args.keep:
                    print("LEDs off.")

            elif args.command == "info":
                effects.show_info(dev)

            elif args.command == "static":
                r, g, b = parse_color(args.color)
                effects.effect_static(dev, r, g, b, keep=args.keep)
                if not args.keep:
                    print(f"Static RGB({r},{g},{b}).")

            elif args.command == "rainbow":
                print("Rainbow mode. Ctrl+C to stop.")
                effects.effect_rainbow(dev, speed=args.speed)

            elif args.command == "breathe":
                r, g, b = parse_color(args.color)
                print(f"Breathing RGB({r},{g},{b}). Ctrl+C to stop.")
                effects.effect_breathe(dev, r, g, b, speed=args.speed)

            elif args.command == "temp":
                if not args.once:
                    print("Temperature mode. Ctrl+C to stop.")
                effects.effect_temp(dev, once=args.once)

    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except SystemExit:
        # Clean exit from signal handler
        pass


if __name__ == "__main__":
    main()
