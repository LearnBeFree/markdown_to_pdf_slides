#!/usr/bin/env bash
# Build slides:  ./build.sh [source.md]
# Requires: pandoc, typst. No hardcoded absolute paths (everything is derived
# from this script's location, so the theme is portable).
#
# Outputs <name>.typ and <name>.pdf next to the SOURCE markdown file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ARG="${1:-example.md}"

# Resolve the source to an absolute path (relative to the caller's cwd).
case "$SRC_ARG" in
  /*) SRC_ABS="$SRC_ARG" ;;
  *)  SRC_ABS="$(pwd)/$SRC_ARG" ;;
esac

if [ ! -f "$SRC_ABS" ]; then
  echo "Source not found: $SRC_ARG" >&2
  exit 1
fi

# Work inside the theme directory so --font-path and cwd-relative asset
# references resolve consistently; outputs still go next to the source.
cd "$SCRIPT_DIR"

SRC_DIR="$(dirname "$SRC_ABS")"
BASE="$(basename "$SRC_ABS")"
BASE="${BASE%.*}"
PDF="$SRC_DIR/$BASE.pdf"

# The generated .typ is an intermediate: it goes to the OS temp dir and is
# removed after the build (PDF stays next to the source). Set
# SLIDES_KEEP_TYP=1 to keep the .typ beside the .md for debugging.
if [ "${SLIDES_KEEP_TYP:-0}" = "1" ]; then
  TYP="$SRC_DIR/$BASE.typ"
  WORK_DIR=""
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slides-build.XXXXXX")"
  trap 'rm -rf "$WORK_DIR"' EXIT
  TYP="$WORK_DIR/$BASE.typ"
fi

FONT_ARGS=()
if [ -d "$SCRIPT_DIR/fonts" ]; then
  FONT_ARGS=(--font-path "$SCRIPT_DIR/fonts")
fi

# Extension tweaks:
#   -raw_tex                      keep `\word` sequences as literal text
#                                 instead of silently dropping raw TeX
#   +wikilinks_title_after_pipe   Obsidian `![[pic.png]]` embeds become real
#                                 images the filter can lay out
THEME_DIR="$SCRIPT_DIR" pandoc "$SRC_ABS" \
  --from markdown-raw_tex+wikilinks_title_after_pipe \
  --to typst \
  --standalone \
  --template "$SCRIPT_DIR/template.typ" \
  --lua-filter "$SCRIPT_DIR/theme-filters.lua" \
  --output "$TYP"

# The filter emits absolute image paths and the .typ can live anywhere, so
# compile against the filesystem root (theme-dir lets the import resolve).
typst compile --root / "${FONT_ARGS[@]}" "$TYP" "$PDF"

echo "Built: $PDF"
