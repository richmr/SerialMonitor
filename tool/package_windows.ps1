# Builds a release SerialMonitor.exe and zips the folder it runs from:
#   dist\SerialMonitor-<version>-windows-x64.zip
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1
#
# The zip includes the Visual C++ runtime DLLs the app needs, so it runs on a
# PC without the VC++ Redistributable installed. Unzip anywhere and run
# SerialMonitor.exe; nothing is installed.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$release = "build\windows\x64\runner\Release"
$out = "dist\SerialMonitor-$version-windows-x64.zip"

flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$stage = Join-Path ([IO.Path]::GetTempPath()) ("SerialMonitor-" + [guid]::NewGuid())
$folder = Join-Path $stage "SerialMonitor"
New-Item -ItemType Directory -Path $folder | Out-Null
try {
    Copy-Item -Path "$release\*" -Destination $folder -Recurse

    foreach ($dll in "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll") {
        $src = Join-Path $env:WINDIR "System32\$dll"
        if (Test-Path $src) {
            Copy-Item $src $folder
        } else {
            Write-Warning "$dll not found; the zip will need the VC++ Redistributable on the target PC."
        }
    }

    New-Item -ItemType Directory -Force -Path dist | Out-Null
    if (Test-Path $out) { Remove-Item $out }
    Compress-Archive -Path $folder -DestinationPath $out
} finally {
    Remove-Item -Recurse -Force $stage
}

Write-Host ""
Write-Host "Wrote $out"
