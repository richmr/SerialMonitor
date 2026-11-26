# Building Serial Monitor on Windows

Flutter compiles the app to a native Windows program. To build it you
need **Git**, **Visual Studio** (Microsoft's C++ compiler, which builds the
window and the serial-port library) and the **Flutter SDK**, which
includes Dart.

Allow about an hour, most of it the Visual Studio download. Run the
commands in **PowerShell**. Windows 10 or 11, 64-bit.

## 1. Git

```powershell
winget install --id Git.Git -e
```

Close and reopen PowerShell afterwards so `git` is on your PATH.

## 2. Visual Studio

You need Visual Studio 2022 (the free Community edition works) with the
**Desktop development with C++** workload. Note that this is Visual Studio,
not VS Code. Either use this command:

```powershell
winget install --id Microsoft.VisualStudio.2022.Community -e --override "--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive"
```

or run the installer from <https://visualstudio.microsoft.com/> and tick
**Desktop development with C++**. If Visual Studio is already installed,
open the **Visual Studio Installer**, choose *Modify* and add that
workload.

## 3. Developer Mode

Flutter needs symlinks to build apps that use plugins, and Windows only
allows those in Developer Mode:

```powershell
start ms-settings:developers
```

Turn on **Developer Mode**.

## 4. Flutter SDK

1. Download the latest stable Flutter SDK zip for Windows from
   <https://docs.flutter.dev/get-started/install/windows/desktop>.
2. Extract it to a folder with no spaces and no special permissions, for
   example `C:\dev\flutter`. Do not use `C:\Program Files`.
3. Add `C:\dev\flutter\bin` to your user PATH:

   ```powershell
   [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\dev\flutter\bin", "User")
   ```

4. Close and reopen PowerShell, then check the version:

   ```powershell
   flutter --version    # needs 3.22 or newer
   ```

## 5. Check the setup

```powershell
flutter doctor -v
```

Only two sections need a green check: **Flutter** and **Visual Studio**.
You can ignore warnings about Android, Chrome or Android Studio. If the
Visual Studio section complains, the C++ workload from step 2 is missing.

```powershell
flutter devices      # should list "Windows (desktop)"
```

If it doesn't, run `flutter config --enable-windows-desktop`.

## 6. Build and run

```powershell
git clone https://github.com/richmr/SerialMonitor.git
cd SerialMonitor
flutter pub get
flutter test              # runs the unit tests
flutter run -d windows    # builds and launches the app (debug)
```

The `windows\` runner folder is already in the repo, so you don't need
`tool\bootstrap.ps1` unless you delete it.

The first build takes a few minutes. Later builds are fast.

## 7. Make a runnable package

```powershell
powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1
```

This writes `dist\SerialMonitor-<version>-windows-x64.zip`. To use it on any
64-bit Windows 10/11 PC, unzip it anywhere and run
`SerialMonitor\SerialMonitor.exe`. Nothing gets installed, and the PC
doesn't need Flutter or Visual Studio. Keep the `.exe` next to its DLLs and
`data\` folder. You can make a shortcut to it, but don't move the `.exe` out
on its own.

If you only want the build without the zip, run
`flutter build windows --release`. The output goes to
`build\windows\x64\runner\Release\`.

## If something goes wrong

- **"Building with plugins requires symlink support":** turn on Developer
  Mode (step 3).
- **`flutter doctor` says Visual Studio is missing components:** add the
  *Desktop development with C++* workload (step 2).
- **"Windows protected your PC" when running the zip on another PC:** the
  build isn't code-signed. Click *More info*, then *Run anyway*. To skip
  this, right-click the zip, choose *Properties*, tick *Unblock* and click
  OK before you extract it.
- **The port won't open, or says access denied:** on Windows only one
  program can hold a COM port at a time. Close Arduino IDE, PlatformIO's
  monitor, PuTTY and the like, or use the upload hook described in the
  README.
- **No ESP32 port in the list:** open Device Manager and look under *Ports
  (COM & LPT)* when you plug the board in. If it shows up under *Other
  devices* with a warning icon, install the driver for its USB chip: Silicon
  Labs CP210x or WCH CH340. Boards with native USB (ESP32-S2/S3/C3/C6) use
  the driver built into Windows.
- **Build stuck or strange errors after switching branches:** run
  `flutter clean`, then `flutter pub get`.
