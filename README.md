# KeyboardLock

A macOS menu bar switch that turns the Mac's built-in keyboard off, so another keyboard (an HHKB, say) can sit on
top of it. External keyboards and the trackpad keep working.

- **Control-Option-Command-L** locks and unlocks. While locked, press it on the external keyboard, or click the
  menu bar icon.
- If the external keyboard disconnects, the built-in one comes back within two seconds, and is locked again when
  the external keyboard returns.
- It won't lock when no external keyboard is connected.
- Quitting unlocks, and so does a reboot. The app remembers that it was locked: started again, it locks as soon
  as an external keyboard is connected.

Touch ID / the power button is not affected.

## Build

```sh
./build.sh           # builds KeyboardLock.app here
./build.sh install   # also copies it to /Applications and starts it
```

Needs the Xcode command line tools. No permissions are asked for: the lock is a `UserKeyMapping` on the built-in
keyboard's HID service, the same thing `hidutil property --set` does.

If the keyboard is ever stuck locked:

```sh
hidutil property --matching '{"Built-In":true,"PrimaryUsagePage":1,"PrimaryUsage":6}' --set '{"UserKeyMapping":[]}'
```

The hotkey is set at the top of `main.swift`.

## License

MIT. See [LICENSE](LICENSE).
