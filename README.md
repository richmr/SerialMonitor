# Serial Monitor

A serial monitor for ESP32 development that keeps **one row per kind of
message** and updates it in place, instead of scrolling everything past you.
Flutter desktop app (Dart) for macOS and Windows.

> **Status: first version, not yet compiled.** The Dart code was written
> without a Flutter toolchain available, so expect to fix a few analyzer
> errors on the first `flutter run`. The ESP32 helper library was compiled
> and run against a mock Arduino core. Run `flutter test` first.

## What it does

- **Aggregate view.** Lines of the same kind share a row: the latest text
  replaces the previous one and `(count)` in front shows how many have
  arrived. Rows stay where they first appeared and flash briefly on update.
- **Grouping.** By `[tag]` if the firmware uses the protocol below;
  otherwise by ESP-IDF tag, arduino-esp32 `file:line`, or by the line's
  shape (numbers ignored), so `Temp: 23.5` and `Temp: 23.7` are one row.
- **Click a row** to open the log of every arrival of that message. Drag
  the divider to resize that panel. **Right-click a row** to copy it or
  delete it (it comes back at the bottom if that message arrives again).
- **Click a value** in that panel to graph it over time (the chart icon on a
  row is a shortcut to its first value).
- **Plot window.** With a value graphed in the detail panel, "Plot in
  window" opens it in a floating plot window (drag its title bar to move it,
  its corner to resize it). Pick another value and "Add to plot" overlays it,
  up to 8. A value whose unit or range doesn't fit the left scale goes on a
  right-hand one; the L/R button on each legend entry moves it, the eye hides
  it, × removes it.
  - Window length: 10s, 30s, 1m, 5m or 20m.
  - Scroll back in time with the scrollbar (click either side of the thumb,
    or the arrows, to move one window length) or a scroll wheel/trackpad. The
    view then stays put while new data arrives; the ⏩ button returns to real
    time.
  - Drag across the chart to zoom in on that stretch; ↶ goes back to the
    previous view.
  - Hover for the values at that moment.
  - The save button stores the plot under the device's name (from its
    `[!hello]`); it reopens by itself the next time that device connects.
    Each value keeps its most recent 50,000 points.
- **Timestamps.** Hover a row for its last arrival, hover a log line for
  that line's arrival. The clock button in the top bar shows them on every
  row; the one in the log panel shows them on every log line.
- **Command box.** Type and press Enter. Autocomplete and the picker button
  are filled from commands the device announces or from a protocol file.
  Hover a command in the picker to see all of it. Once a device turns out to
  speak the protocol, the monitor sends `?` by itself (once per connection
  and after each restart) so its commands are always loaded; turn this off
  in the menu.
- **Save the stream.** The save button writes every line received and sent
  (sent ones marked `>`), with timestamps, to a file. The last 200,000 lines
  are kept in memory; for longer captures use menu → "Record serial stream
  to file…", which appends each line as it arrives until you stop it.
- **Zoom.** Cmd + / Cmd - / Cmd 0 on macOS (Ctrl on Windows).
- **Survives re-flashing.** See below.

## Setup (once per machine)

Needs Flutter 3.22 or newer, plus Xcode and CocoaPods on macOS or Visual
Studio with "Desktop development with C++" on Windows.
New to Flutter? See [docs/MAC_SETUP.md](docs/MAC_SETUP.md) or
[docs/WINDOWS_SETUP.md](docs/WINDOWS_SETUP.md).

```sh
tool/bootstrap.sh                                               # macOS
powershell -ExecutionPolicy Bypass -File tool\bootstrap.ps1     # Windows
```

This runs `flutter create` to generate the `macos/` and `windows/` runner
folders (commit them afterwards) and, on macOS, turns off the App Sandbox so
the app can open serial devices. Then:

```sh
flutter test
flutter run -d macos      # or: -d windows
```

## Packaged builds

`tool/package_macos.sh` makes a `.dmg` and `tool\package_windows.ps1` a
`.zip` that runs on a PC without Flutter, both in `dist/`. The GitHub
**Release** workflow builds both. See [docs/PACKAGING.md](docs/PACKAGING.md)
for signing, opening unsigned builds and regenerating the app icon.

## ESP32 defaults

115200 baud, 8N1, no flow control, DTR and RTS asserted (which leaves the
auto-reset circuit idle). USB ports with Espressif, CP210x, CH340 or FTDI
vendor IDs are listed first and one is preselected. The restart button
pulses EN through RTS. Baud, DTR and RTS can be changed from the toolbar.

## Re-flashing while the monitor is open

Three things work together:

1. **Auto-reconnect.** If the port disappears or errors (reset, unplug, a
   native-USB board re-enumerating), the monitor shows "Waiting for device…"
   and reopens the port as soon as it can, retrying twice a second.
2. **Upload hook.** A USB-UART bridge (CP210x / CH340) never disappears, and
   on Windows only one program can hold a COM port, so the uploader needs the
   monitor to let go. Add this to the firmware project's `platformio.ini`:

   ```ini
   extra_scripts = post:/path/to/SerialMonitor/tool/pio_smp_hook.py
   ```

   Before `pio run -t upload` it asks the monitor (TCP `127.0.0.1:47800`) to
   release the port, and afterwards to take it back. If the upload fails and
   never says "resume", the monitor takes the port back after 120 s.
3. **Manual release.** The pause button does the same by hand.

Rows not seen since the device restarted are dimmed; "Clear rows when the
device restarts" in the menu removes them instead.

## Protocol

[docs/PROTOCOL.md](docs/PROTOCOL.md) defines SMP v1: `[tag] key=value …`
lines from the device, plain command lines to it, and `[!hello]` / `[!cmd]`
lines that let the device announce its commands.

`esp32/SerialMonitorProtocol/src/smp.h` is a header-only helper for firmware;
`esp32/examples/basic` is a PlatformIO example that uses it.
`esp32/examples/testbench` is test firmware that exercises every feature
(graphable waves, all log levels, row grouping in each format, commands,
restarts); load `examples/testbench.smp.json` with it. To use it in
another project, copy `smp.h` or add
`lib_deps = symlink:///path/to/SerialMonitor/esp32/SerialMonitorProtocol`.

## Layout

```
lib/protocol/   line parser, protocol file model          (pure Dart)
lib/model/      message store: groups, logs, value series
lib/serial/     session (reconnect logic), libserialport backend, upload-hook server
lib/ui/         aggregate view, detail panel, chart, command bar, toolbar
test/           parser, store, session (with a fake port), UI smoke test
tool/           bootstrap, packaging and icon scripts, PlatformIO upload hook
esp32/          firmware helper library and example
```

## Not in this version

Saved settings (port, baud, window), keyboard history in the command box,
a plot window that can leave the main window (Flutter's multi-window support
is not yet in a stable release), and matching a re-enumerated
device that comes back under a different port name.
