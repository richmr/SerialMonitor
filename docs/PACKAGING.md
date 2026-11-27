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

## Releases from GitHub

You don't need a Windows PC, or even your Mac, to make a release. The
**Release** workflow (`.github/workflows/release.yml`) builds both packages
on GitHub's machines and attaches them to a draft release. It only runs
when you start it:

1. Set `version:` in `pubspec.yaml` to the new version and push it to
   `main`. The release is tagged `v<version>`, and the run stops early if
   that tag or release already exists.
2. On the repo's *Actions* tab, choose *Release*, pick the branch and click
   *Run workflow*. Leave *Create a draft GitHub release* ticked.
3. When it finishes, open the *Releases* page. The draft holds the `.dmg`,
   the `.zip` and `SHA256SUMS.txt`, with notes generated from the merged
   pull requests. Edit the notes if you like, then click *Publish release*.
   The tag is created on the commit that was built when you publish.

Untick *Create a draft GitHub release* to just build: the packages are then
only kept as the run's *Artifacts* (each is a zip holding the package).

The workflow file has to be on `main` before the *Run workflow* button
appears, though any branch can then be built. On a private repo a run uses
roughly 20 Windows-equivalent minutes plus about 10 macOS minutes, which
count 10x against the free monthly allowance. Public repos are free.

### Signing on GitHub

The GitHub builds are unsigned in the same way as local ones, and need no
certificate or secrets:

- **macOS**: the Xcode project uses `CODE_SIGN_IDENTITY = "-"`, so the
  build is *ad-hoc signed*. That needs no certificate, and is required for
  the app to run at all on Apple Silicon. But it has no Developer ID and
  isn't notarized, so Gatekeeper blocks the downloaded app until the user
  allows it (see [Opening an unsigned build](#opening-an-unsigned-build-on-another-mac)).
  The run log prints the signature (`Signature=adhoc`) and the
  architectures (`x86_64 arm64`).
- **Windows**: no Authenticode signature, so SmartScreen warns.

To sign the macOS build in CI later, you'd need a paid Apple Developer
account. Export the *Developer ID Application* certificate as a `.p12`,
store it and an App Store Connect API key as repository secrets, import the
certificate into a temporary keychain in the macOS job, and set
`SIGN_IDENTITY` (and notarize with `xcrun notarytool submit --key ...`)
before `tool/package_macos.sh` runs.

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
