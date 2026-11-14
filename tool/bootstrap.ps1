# One-time setup on Windows: generates the native runner folders.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tool\bootstrap.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

git diff --quiet
$dirty = $LASTEXITCODE -ne 0
git diff --cached --quiet
if ($dirty -or ($LASTEXITCODE -ne 0)) {
    Write-Error "Commit or stash your changes first: this script restores tracked files."
    exit 1
}

flutter create --platforms=macos,windows --project-name serial_monitor --org dev.richmr .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# flutter create may rewrite files that already exist; put ours back.
git checkout -- .

flutter pub get
Write-Host ""
Write-Host "Ready. Run it with:  flutter run -d windows"
Write-Host "Commit the generated macos/ and windows/ folders."
