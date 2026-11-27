# Development notes

## Setup

Requirements: Flutter 3.22 or newer, plus Xcode and CocoaPods on macOS, or
Visual Studio with "Desktop development with C++" on Windows. Step-by-step
machine setup is in [MAC_SETUP.md](MAC_SETUP.md) and
[WINDOWS_SETUP.md](WINDOWS_SETUP.md).

```sh
flutter test
flutter run -d macos      # or: -d windows
```

The `macos/` and `windows/` runner folders are committed. If you need to
regenerate them, run the bootstrap script. It runs `flutter create` and, on
macOS, turns off the App Sandbox so the app can open serial devices.

```sh
tool/bootstrap.sh                                               # macOS
powershell -ExecutionPolicy Bypass -File tool\bootstrap.ps1     # Windows
```

Packaging, signing and the app icon are covered in [PACKAGING.md](PACKAGING.md).

## Layout

```
lib/protocol/   line parser, protocol file model          (pure Dart)
lib/model/      message store: groups, logs, value series
lib/serial/     session (reconnect logic), libserialport backend, upload-hook server
lib/ui/         aggregate view, detail panel, chart, command bar, toolbar
test/           parser, store, session (with a fake port), UI smoke test
tool/           bootstrap, packaging and icon scripts, PlatformIO upload hook
esp32/          firmware helper library (smp.h) and examples
examples/       protocol description files (*.smp.json) for the examples
docs/           protocol spec, setup and packaging guides, README images
```

## Test firmware

`esp32/examples/testbench` exercises every feature: graphable waves, every
log level, row grouping in each line format, commands, errors and restarts.
`examples/testbench.smp.json` is its protocol file, for testing
"Load protocol file…". The README screenshots and GIFs in `docs/images/` were
taken with this firmware running.

## Not in this version

- Saved settings (port, baud, window size).
- Keyboard history in the command box.
- A plot window that can leave the main window. Flutter's multi-window
  support isn't in a stable release yet.
- Reconnecting to a re-enumerated device that comes back under a different
  port name.
