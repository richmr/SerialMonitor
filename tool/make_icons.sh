#!/usr/bin/env bash
# Renders the macOS and Windows app icons from assets/icon/icon.svg.
# Needs rsvg-convert and ImageMagick:  brew install librsvg imagemagick
# Run from anywhere:  tool/make_icons.sh   (then commit the changed icons)
set -euo pipefail
cd "$(dirname "$0")/.."

src=assets/icon/icon.svg
mac=macos/Runner/Assets.xcassets/AppIcon.appiconset
win=windows/runner/resources/app_icon.ico

for tool in rsvg-convert magick; do
  command -v "$tool" >/dev/null || { echo "Missing $tool (brew install librsvg imagemagick)" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# macOS: the full canvas, margin and shadow included, as Apple's grid expects.
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" -h "$size" "$src" -o "$mac/app_icon_$size.png"
done

# Windows: icons fill their square, so crop to the tile and drop the shadow.
sed -e 's/viewBox="0 0 1024 1024"/viewBox="96 96 832 832"/' \
    -e 's/ filter="url(#shadow)"//' "$src" > "$tmp/win.svg"
pngs=()
for size in 16 20 24 32 40 48 64 128 256; do
  rsvg-convert -w "$size" -h "$size" "$tmp/win.svg" -o "$tmp/win_$size.png"
  pngs+=("$tmp/win_$size.png")
done
magick "${pngs[@]}" "$win"

echo "Wrote $mac/app_icon_*.png and $win"
