# Packaging and releases

| Platform | Command | Output |
|----------|---------|--------|
| macOS | `tool/package_macos.sh` | `dist/SerialMonitor-<version>-macos.dmg` |
| Windows | `powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1` | `dist\SerialMonitor-<version>-windows-x64.zip` |

The version comes from `version:` in `pubspec.yaml`. Each script runs a
release build and packs the result. You can only build each platform on
that platform. For machine setup, see [MAC_SETUP.md](MAC_SETUP.md) and
[WINDOWS_SETUP.md](WINDOWS_SETUP.md).

## macOS

The disk image holds `Serial Monitor.app` and an Applications shortcut.
Drag the app across to install it.

By default the app is *ad-hoc signed*. That's fine on the Mac that built
it. On another Mac, Gatekeeper blocks a downloaded ad-hoc-signed app (see
below). To ship a build that opens without warnings, you need an Apple
Developer account and a *Developer ID Application* certificate in your
keychain:

```sh
# once: save notarization credentials under a name of your choice
xcrun notarytool store-credentials smp-notary --apple-id you@example.com --team-id TEAMID

SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=smp-notary tool/package_macos.sh
```

### Opening an unsigned build on another Mac

On the first launch, macOS says the app "cannot be opened" or "is damaged".
Either:

- Open **System Settings → Privacy & Security**, scroll to the message
  about Serial Monitor and click **Open Anyway**, or
- Remove the download quarantine flag in Terminal:
  `xattr -dr com.apple.quarantine "/Applications/Serial Monitor.app"`

You only need to do this once per copy.

## Windows

The zip holds a `SerialMonitor` folder with `SerialMonitor.exe`, its DLLs
(including the Visual C++ runtime) and a `data` folder. Unzip it anywhere
and run the `.exe`. Nothing gets installed.

The build isn't code-signed, so SmartScreen may say "Windows protected your
PC". Click *More info*, then *Run anyway*. Unblocking the zip in its
Properties before you extract it avoids this.

## Windows build from GitHub

You don't need a Windows PC to make the Windows package. The **Windows
package** workflow (`.github/workflows/windows-package.yml`) runs the tests
and `tool\package_windows.ps1` on one of GitHub's Windows machines. It only
runs when you start it:

1. Push the branch you want built. The workflow file itself has to be on
   `main` before the *Run workflow* button appears, though any branch can
   then be built.
2. On the repo's *Actions* tab, choose *Windows package*, pick that branch
   and click *Run workflow*.
3. When it finishes, download `SerialMonitor-Windows` from the run's
   *Artifacts* section. It's a zip that holds the package zip.

On a private repo a run uses roughly 20 of the free monthly Actions minutes,
because Windows minutes count double. Build the macOS `.dmg` locally with
`tool/package_macos.sh`.

The CI build is unsigned, just like a local build.

## App icon

The icon source is `assets/icon/icon.svg`. After you edit it, regenerate
the platform icons and commit them:

```sh
brew install librsvg imagemagick   # once
tool/make_icons.sh
```

This writes `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png` (full
canvas with Apple's margin and shadow) and
`windows/runner/resources/app_icon.ico` (cropped to the tile, 16–256 px).
