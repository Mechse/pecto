#!/usr/bin/env bash
#
# Regenerates the menu-bar icon asset PNGs from design/menubaricon.svg.
#
#     ./scripts/make-menubar-icon.sh
#
# Three image sets are produced, because the running state mixes a
# menu-bar-tinted glyph with a fixed green accent and a single template image
# cannot express that (see Pecto/MenuBarIcon.swift):
#
#     MenuBarIcon        both sparkles   (idle)
#     MenuBarIconGlyph   large sparkle   (running, tinted with labelColor)
#     MenuBarIconAccent  small sparkle   (running, tinted brand green)
#
# Rasterising is done by scripts/svg2png.swift — see the note at the top of
# that file for why it is not inkscape or ImageMagick.
#
set -euo pipefail

cd "$(dirname "$0")/.."
SVG="design/menubaricon.svg"
ASSETS="Pecto/Assets.xcassets"
BASE=18 # points; the standard status-item box

command -v swift >/dev/null || { echo "error: swift not on PATH" >&2; exit 1; }
[[ -f "$SVG" ]] || { echo "error: $SVG not found" >&2; exit 1; }

# name -> svg element id to export ("" exports the whole page)
render() {
  local name=$1 id=$2
  local dir="$ASSETS/$name.imageset"
  mkdir -p "$dir"

  # 1x and 2x only — macOS has no 3x displays, and Xcode drops a 3x slice.
  for scale in 1 2; do
    local px=$((BASE * scale))
    local out="$dir/icon"
    [[ $scale -eq 1 ]] && out="$out.png" || out="$out@${scale}x.png"

    swift scripts/svg2png.swift "$SVG" "$out" "$px" ${id:+"$id"}
  done

  cat > "$dir/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "scale" : "1x", "filename" : "icon.png" },
    { "idiom" : "universal", "scale" : "2x", "filename" : "icon@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
JSON

  echo "  $name"
}

echo "==> Exporting menu-bar icon assets from $SVG"
render MenuBarIcon ""
render MenuBarIconGlyph glyph
render MenuBarIconAccent accent
echo "Done."
