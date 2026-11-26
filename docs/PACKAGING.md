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

## Building both from GitHub

The **Release** workflow (`.github/workflows/release.yml`) runs the tests
and both packaging scripts on GitHub's macOS and Windows machines, so you
can get a Windows build without a Windows PC.

- **By hand:** on the repo's *Actions* tab, choose *Release* and click
  *Run workflow*. When it finishes, download the `.dmg` and `.zip` from the
  run's *Artifacts* section.
- **Tagged release:** bump `version:` in `pubspec.yaml`, commit, then

  ```sh
  git tag v0.2.0 && git push origin v0.2.0
  ```

  The workflow attaches both packages to a GitHub release for that tag.

CI builds are unsigned, just like local builds without `SIGN_IDENTITY`.

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
