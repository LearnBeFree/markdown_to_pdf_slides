#!/usr/bin/env bash
# Build slides:  ./build.sh [source.md]
# Requires: pandoc, typst. No hardcoded absolute paths (everything is derived
# from this script's location, so the theme is portable).
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

# Work inside the theme directory so the generated .typ can import
# slides-theme.typ, and so --font-path / assets resolve consistently.
cd "$SCRIPT_DIR"

BASE="$(basename "$SRC_ABS")"
BASE="${BASE%.*}"
TYP="${BASE}.typ"
PDF="${BASE}.pdf"

FONT_ARGS=()
if [ -d "$SCRIPT_DIR/fonts" ]; then
  FONT_ARGS=(--font-path "$SCRIPT_DIR/fonts")
fi

pandoc "$SRC_ABS" \
  --from markdown \
  --to typst \
  --standalone \
  --template "$SCRIPT_DIR/template.typ" \
  --lua-filter "$SCRIPT_DIR/theme-filters.lua" \
  --output "$TYP"

# Pandoc hardcodes a cramped `inset: <n>pt` on every table. Typst cannot
# override an explicit argument with a set-rule (and rebuilding the table in a
# show-rule recurses), so widen the cell padding in the generated file.
sed -i -E 's/inset: [0-9.]+pt/inset: (x: 0.95em, y: 0.72em)/g' "$TYP"

typst compile "${FONT_ARGS[@]}" "$TYP" "$PDF"

echo "Built: $SCRIPT_DIR/$PDF"
