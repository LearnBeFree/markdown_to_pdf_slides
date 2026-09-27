#!/usr/bin/env bash
# Build slides:  ./build.sh [source.md]
# Requires: pandoc, typst. No hardcoded absolute paths (everything is derived
# from this script's location, so the theme is portable).
#
# Outputs <name>.pdf next to the SOURCE markdown file (the intermediate
# .typ goes to a temp dir; see below).
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

# The generated .typ is an intermediate: it goes to a temp dir that is
# removed after the build (PDF stays next to the source). Set
# SLIDES_KEEP_TYP=1 to keep the .typ beside the .md for debugging.
#
# Typst needs ONE root that contains the .typ, the theme import and every
# referenced image. On Unix "/" always qualifies. Windows drives have no
# common root (repo on C:, deck on E:), so there the build is staged on the
# SOURCE's drive: workdir next to the source (auto-deleted), theme copied
# into it, root = the source's drive root (e.g. "E:/").
IS_WIN=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; esac

if [ "$IS_WIN" = 1 ]; then
  ROOT="$(cygpath -m "$SRC_ABS")"
  ROOT="${ROOT:0:3}"
  if [[ ! "$ROOT" =~ ^[A-Za-z]:/$ ]]; then
    echo "Не удалось определить диск деки ($SRC_ABS); UNC-пути (\\\\сервер) не поддерживаются" >&2
    exit 1
  fi
  WORK_DIR="$(mktemp -d "$SRC_DIR/.slides-build.XXXXXX")"
  TYP="$WORK_DIR/$BASE.typ"
  cp "$SCRIPT_DIR/slides-theme.typ" "$WORK_DIR/slides-theme.typ"
  THEME_FOR_PANDOC="$(cygpath -m "$WORK_DIR")"
else
  ROOT="/"
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slides-build.XXXXXX")"
  TYP="$WORK_DIR/$BASE.typ"
  THEME_FOR_PANDOC="$SCRIPT_DIR"
fi
if [ "${SLIDES_KEEP_TYP:-0}" = "1" ]; then
  TYP="$SRC_DIR/$BASE.typ"
fi
trap 'rm -rf "$WORK_DIR"' EXIT

FONT_ARGS=()
if [ -d "$SCRIPT_DIR/fonts" ]; then
  FONT_ARGS=(--font-path "$SCRIPT_DIR/fonts")
fi

# Extension tweaks:
#   -raw_tex                      keep `\word` sequences as literal text
#                                 instead of silently dropping raw TeX
#   +wikilinks_title_after_pipe   Obsidian `![[pic.png]]` embeds become real
#                                 images the filter can lay out
THEME_DIR="$THEME_FOR_PANDOC" pandoc "$SRC_ABS" \
  --from markdown-raw_tex+wikilinks_title_after_pipe \
  --to typst \
  --standalone \
  --template "$SCRIPT_DIR/template.typ" \
  --lua-filter "$SCRIPT_DIR/theme-filters.lua" \
  --output "$TYP"

# The filter emits absolute image paths and the staged .typ is on the
# source's drive, so root covers everything (Unix: "/", Windows: "E:/").
typst compile --root "$ROOT" "${FONT_ARGS[@]}" "$TYP" "$PDF"

echo "Built: $PDF"
