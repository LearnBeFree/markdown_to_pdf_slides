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

# Stage the build: a temp workdir holds the generated .typ plus a copy of
# slides-theme.typ, so the source imports the theme as a SIBLING file —
# no absolute theme paths, no env vars (both proved fragile with non-ASCII
# paths on Windows). The workdir is auto-deleted; only the PDF stays next
# to the source. Set SLIDES_KEEP_TYP=1 to keep the .typ (and the theme
# copy) beside the .md for debugging.
#
# Typst needs ONE root that contains the .typ, the theme and every image.
# On Unix "/" always qualifies. Windows drives have no common root (repo
# on C:, deck on E:), so there the workdir sits next to the source and
# root = the source's drive root (e.g. "E:/").
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
else
  ROOT="/"
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slides-build.XXXXXX")"
fi

if [ "${SLIDES_KEEP_TYP:-0}" = "1" ]; then
  TYP="$SRC_DIR/$BASE.typ"
else
  TYP="$WORK_DIR/$BASE.typ"
fi
TYP_DIR="$(dirname "$TYP")"
if [ "$TYP_DIR" != "$SCRIPT_DIR" ]; then
  cp "$SCRIPT_DIR/slides-theme.typ" "$TYP_DIR/"
fi
trap 'rm -rf "$WORK_DIR"' EXIT

FONT_ARGS=()
if [ -d "$SCRIPT_DIR/fonts" ]; then
  FONT_ARGS=(--font-path "$SCRIPT_DIR/fonts")
fi

# Pre-scan image references and check them HERE with bash: on Windows,
# Lua's io.open inside native pandoc.exe goes through the ANSI code page
# and cannot see non-ASCII (UTF-8) paths, so the filter alone can't tell a
# missing image from a Cyrillic one. The missing refs travel to the filter
# via --metadata (argv — the one Unicode-safe channel into pandoc), joined
# with \031 (control chars cannot appear in filenames). The filter then
# keeps rendering friendly placeholders instead of failing in typst.
MISSING_ARGS=()
{
  # ![alt](path) — including <path with spaces> "title"
  { grep -oE '!\[[^]]*\]\([^)]+\)' "$SRC_ABS" 2>/dev/null \
      | sed -E 's/^!\[[^]]*\]\(//; s/\)$//; s/^<//; s/>.*$//; s/[[:space:]]*".*$//' || true; }
  # Obsidian ![[p.png]] / [[p|alias]] / [[p]]
  { grep -oE '!?\[\[[^]]+\]\]' "$SRC_ABS" 2>/dev/null \
      | sed -E 's/^!?\[\[//; s/\]\]$//; s/\|.*$//' || true; }
  # cover from frontmatter
  { grep -iE '^[[:space:]]*cover-image:' "$SRC_ABS" 2>/dev/null \
      | sed -E 's/^[^:]*:[[:space:]]*//; s/"//g' || true; }
} | while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  dec="$(printf '%s' "$ref" | sed 's/%20/ /g; s/%5B/[/g; s/%5D/]/g')"
  found=0
  for p in "$ref" "$dec"; do
    case "$p" in /*) full="$p" ;; *) full="$SRC_DIR/$p" ;; esac
    if [ -f "$full" ]; then found=1; break; fi
  done
  # NB: an `if` (not `[ ] && printf`) so the loop body never returns false
  # under set -e when the last ref happens to exist.
  if [ "$found" = 0 ]; then printf '%s\n' "$ref"; fi
done > "$WORK_DIR/missing.txt"

if [ -s "$WORK_DIR/missing.txt" ]; then
  # \037 (octal) == byte 31 decimal == Lua "\31" (unit separator)
  MISSING_ARGS=(--metadata "missing-images=$(paste -sd $'\037' "$WORK_DIR/missing.txt")")
fi

# Extension tweaks:
#   -raw_tex                      keep `\word` sequences as literal text
#                                 instead of silently dropping raw TeX
#   +wikilinks_title_after_pipe   Obsidian `![[pic.png]]` embeds become real
#                                 images the filter can lay out
pandoc "$SRC_ABS" \
  "${MISSING_ARGS[@]}" \
  --from markdown-raw_tex+wikilinks_title_after_pipe \
  --to typst \
  --standalone \
  --template "$SCRIPT_DIR/template.typ" \
  --lua-filter "$SCRIPT_DIR/theme-filters.lua" \
  --output "$TYP"

# The filter emits root-relative image paths and the staged .typ sits next
# to its theme copy, so root covers everything (Unix: "/", Windows: "E:/").
typst compile --root "$ROOT" "${FONT_ARGS[@]}" "$TYP" "$PDF"

echo "Built: $PDF"
