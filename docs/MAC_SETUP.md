# Preparing a Mac to build Serial Monitor

Flutter is Google's UI toolkit; apps are written in Dart and compiled to a
native macOS app. To build one you need three things: **Xcode** (Apple's
compiler), **CocoaPods** (pulls in native plugin code, here the serial-port
library) and the **Flutter SDK** itself (which includes Dart).

Allow about an hour, most of it the Xcode download. Commands go in Terminal.

## 1. Xcode

1. Install **Xcode** from the App Store (large download; the full app is
   needed, not just the command-line tools).
2. Point the command-line tools at it and finish its setup:

   ```sh
   sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
   sudo xcodebuild -license accept
   ```

## 2. Homebrew (skip if `brew --version` already works)

Homebrew is the usual Mac package manager and makes the next two steps one
line each. Install it with the command shown at <https://brew.sh>, then
follow the "Next steps" it prints so `brew` is on your PATH.

## 3. CocoaPods

```sh
brew install cocoapods
pod --version        # should print a version number
```

## 4. Flutter SDK

```sh
brew install --cask flutter
flutter --version    # needs 3.22 or newer for this project
```

Prefer not to use Homebrew? Follow the manual install at
<https://docs.flutter.dev/get-started/install/macos/desktop> instead
(download the SDK, unzip it to `~/development`, add
`~/development/flutter/bin` to your PATH in `~/.zshrc`).

## 5. Check the setup

```sh
flutter doctor -v
```

For this project only two sections need a green check: **Flutter** and
**Xcode**. Warnings about Android toolchain, Android Studio or Chrome can be
ignored: those are for phone and web apps. If the Xcode section complains,
it says exactly which command to run.

Then confirm the Mac is offered as a build target:

```sh
flutter devices      # should list "macOS (desktop)"
```

If it is missing: `flutter config --enable-macos-desktop`.

## 6. Editor (optional)

VS Code with the **Flutter** extension (it installs the Dart extension too)
gives error squiggles, a Run button and hot reload. Nothing else is needed;
everything also works from Terminal.

## 7. Build Serial Monitor

```sh
git clone https://github.com/richmr/SerialMonitor.git
cd SerialMonitor
tool/bootstrap.sh         # one time: creates macos/ and windows/, fetches packages
flutter analyze           # lists compile errors, if any
flutter test              # runs the unit tests
flutter run -d macos      # builds and launches the app
```

After `tool/bootstrap.sh`, commit the new `macos/` and `windows/` folders.

The first `flutter run` takes a few minutes (it builds the serial library
and runs CocoaPods); later runs are fast.

## Everyday commands

| Command | What it does |
|---------|--------------|
| `flutter run -d macos` | Build and launch in debug mode. In that terminal, `r` hot-reloads code changes, `R` restarts the app, `q` quits. |
| `flutter analyze` | Type-check and lint without building. |
| `flutter test` | Run the tests in `test/`. |
| `flutter pub get` | Fetch packages after `pubspec.yaml` changes. |
| `flutter build macos` | Release build, written to `build/macos/Build/Products/Release/`. |
| `flutter upgrade` | Update Flutter itself. |
| `flutter clean` | Delete build output when a build gets stuck; follow with `flutter pub get`. |

## If something goes wrong

- **`pod install` fails or CocoaPods errors:** run `pod repo update`, then
  `flutter clean && flutter pub get` and try again.
- **"Operation not permitted" or the port will not open:** check that
  `tool/bootstrap.sh` ran on this Mac; it turns off the App Sandbox in
  `macos/Runner/*.entitlements`, which otherwise blocks serial devices.
- **No ESP32 port in the list:** boards with a CH340 or CP210x chip may need
  the vendor's USB driver on older macOS versions; check that a
  `/dev/cu.usbserial-*` or `/dev/cu.usbmodem*` device appears when you plug
  the board in (`ls /dev/cu.*`).
- **Analyzer errors on first build:** expected for this first version, which
  was written without a compiler. Paste the `flutter analyze` output to
  Claude to get them fixed.
