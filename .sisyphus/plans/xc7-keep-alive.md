# XC7 Keep-Alive Fix — Prevent LED Auto-Restore

## TL;DR

> **Quick Summary**: Device firmware restores default lighting after HID command timeout. Fix by adding `--keep` loop mode to `off` and `static` commands, and making launchd plist a persistent daemon.
> 
> **Deliverables**: 3 file edits
> **Estimated Effort**: Quick (5 min)
> **Parallel Execution**: NO — sequential single task

---

## Context

After running `icue-xc7 off`, LEDs turn off but automatically re-enable after a timeout. The XC7 firmware has a built-in default lighting mode that activates when it stops receiving HID commands. The fix is to periodically resend the RGB command.

---

## Work Objectives

### Must Have
- `icue-xc7 off --keep` loops and resends off every 2 seconds (Ctrl+C to stop)
- `icue-xc7 static FF0000 --keep` same for static color
- `icue-xc7 off` (without --keep) still works as one-shot
- launchd plist uses `off --keep` and `KeepAlive` for persistent daemon

### Must NOT Have
- No changes to rainbow/breathe/temp (they already loop)
- No new files

---

## TODOs

- [x] 1. Add --keep loop mode to off and static commands

  **What to do**:

  **File `icue_xc7/effects.py`** — modify two functions:
  ```python
  def effect_off(dev: XC7Device, keep: bool = False):
      """Turn off all LEDs. If keep=True, resend periodically."""
      dev.set_all_rgb(0, 0, 0)
      while keep:
          time.sleep(2.0)
          dev.set_all_rgb(0, 0, 0)

  def effect_static(dev: XC7Device, r: int, g: int, b: int, keep: bool = False):
      """Set all LEDs to a static color. If keep=True, resend periodically."""
      dev.set_all_rgb(r, g, b)
      while keep:
          time.sleep(2.0)
          dev.set_all_rgb(r, g, b)
  ```

  **File `icue_xc7/cli.py`** — add `--keep` flag to `off` and `static` subparsers:
  ```python
  # Replace the off parser line:
  p_off = sub.add_parser("off", help="Turn off all LEDs")
  p_off.add_argument("--keep", action="store_true", help="Keep sending off command (Ctrl+C to stop)")

  # Add --keep to existing static parser:
  p_static.add_argument("--keep", action="store_true", help="Keep resending color (Ctrl+C to stop)")
  ```

  Update the dispatch in `main()`:
  ```python
  if args.command == "off":
      if args.keep:
          print("LEDs off (keep-alive). Ctrl+C to stop.")
      else:
          print("LEDs off.")
      effects.effect_off(dev, keep=args.keep)

  elif args.command == "static":
      r, g, b = parse_color(args.color)
      if args.keep:
          print(f"Static RGB({r},{g},{b}) (keep-alive). Ctrl+C to stop.")
      else:
          print(f"Static RGB({r},{g},{b}).")
      effects.effect_static(dev, r, g, b, keep=args.keep)
  ```

  **File `com.cyonsun.icue-xc7.plist`** — change to persistent daemon:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.cyonsun.icue-xc7</string>
      <key>ProgramArguments</key>
      <array>
          <string>/Users/cyonsun/Documents/Code/ICUE-MAC/.venv/bin/icue-xc7</string>
          <string>off</string>
          <string>--keep</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
      <key>StandardOutPath</key>
      <string>/tmp/icue-xc7.log</string>
      <key>StandardErrorPath</key>
      <string>/tmp/icue-xc7.err</string>
  </dict>
  </plist>
  ```

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Acceptance Criteria**:
  - [ ] `icue-xc7 off --keep` keeps LEDs off persistently (test for 30+ seconds)
  - [ ] `icue-xc7 off` (no --keep) still works as one-shot
  - [ ] `icue-xc7 static FF0000 --keep` keeps red persistently
  - [ ] `icue-xc7 --help` shows --keep flag on off and static

  **Commit**: YES — `fix(xc7): add --keep mode to prevent firmware LED auto-restore`

---

## Success Criteria

```bash
icue-xc7 off --keep    # LEDs stay off indefinitely, Ctrl+C to stop
icue-xc7 off           # One-shot off (still works)
icue-xc7 static FF0000 --keep  # Persistent red
```
