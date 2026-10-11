#!/usr/bin/env bash
# tests/run.sh — regression harness for the slides pipeline.
#
#   tests/run.sh            run the whole corpus, diff against goldens
#   tests/run.sh -u         (re)generate goldens from current behavior
#   tests/run.sh 06-setext  run decks matching a substring
#
# Each tests/decks/<name>.md is staged into tests/.work/<name>/ together with
# tests/assets/, built with SLIDES_KEEP_TYP=1, and three artifacts are
# compared against tests/golden/<name>.*:
#   .typ    generated Typst (absolute paths normalized to <<WORK>>/<<REPO>>)
#   .err    normalized stderr (warnings, notices)
#   .pages  PDF page count (pdfinfo; skipped silently if unavailable)
# A sibling marker file <name>.md.crlf stages the deck with CRLF endings,
# <name>.md.bom prepends a UTF-8 BOM, and <name>.md.fail (first line =
# grep -E pattern, rest = comment) declares a deck that MUST fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/tests"
DECKS="$TESTS/decks"
GOLDEN="$TESTS/golden"
WORK="$TESTS/.work"

UPDATE=0
FILTER=""
for a in "$@"; do
  case "$a" in
    -u|--update) UPDATE=1 ;;
    *) FILTER="$a" ;;
  esac
done

[ -d "$TESTS/assets" ] || "$TESTS/make-assets.sh"
mkdir -p "$WORK"

normalize() { # portable goldens: strip machine-specific absolute paths
  sed -e "s|$WORK|<<WORK>>|g" -e "s|$ROOT|<<REPO>>|g" "$1"
}

pass=0; fail=0; failed_names=()

for deck in "$DECKS"/*.md; do
  name="$(basename "$deck" .md)"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
  stage="$WORK/$name"
  rm -rf "$stage"; mkdir -p "$stage"
  cp "$deck" "$stage/deck.md"
  cp -r "$TESTS/assets" "$stage/assets"
  [ -f "$DECKS/$name.md.crlf" ] && sed -i 's/$/\r/' "$stage/deck.md"
  if [ -f "$DECKS/$name.md.bom" ]; then
    printf '\xef\xbb\xbf' > "$stage/deck.md.tmp"
    cat "$stage/deck.md" >> "$stage/deck.md.tmp" && mv "$stage/deck.md.tmp" "$stage/deck.md"
  fi

  if ( cd "$ROOT" && SLIDES_KEEP_TYP=1 ./build.sh "$stage/deck.md" \
       >"$stage/out.log" 2>"$stage/err.log" ); then
    echo 0 > "$stage/exit"
  else
    echo $? > "$stage/exit"
  fi

  # drop the two staging leftovers that are NOT part of the contract
  rm -f "$stage/deck.typ"~ 2>/dev/null || true

  want_fail=0
  if [ -f "$DECKS/$name.md.fail" ]; then
    want_fail=1; failpat="$(head -1 "$DECKS/$name.md.fail")"
  fi

  reason=""
  if [ "$want_fail" = 1 ]; then
    [ "$(cat "$stage/exit")" != "0" ] || reason="expected failure but build succeeded"
    normalize "$stage/err.log" | grep -qE "$failpat" \
      || reason="${reason:+$reason; }stderr does not match /$failpat/"
  else
    [ "$(cat "$stage/exit")" = "0" ] || reason="build exited $(cat "$stage/exit")"
  fi

  if [ -f "$stage/deck.typ" ]; then
    normalize "$stage/deck.typ" > "$stage/deck.typ.norm"
  else
    : > "$stage/deck.typ.norm"
  fi
  normalize "$stage/err.log" > "$stage/err.norm"

  pages=""
  if command -v pdfinfo >/dev/null 2>&1 && [ -f "$stage/deck.pdf" ]; then
    pages="$(pdfinfo "$stage/deck.pdf" 2>/dev/null | awk '/^Pages/{print $2}')"
  fi

  if [ "$UPDATE" = 1 ]; then
    mkdir -p "$GOLDEN"
    cp "$stage/deck.typ.norm" "$GOLDEN/$name.typ"
    cp "$stage/err.norm" "$GOLDEN/$name.err"
    printf '%s\n' "$pages" > "$GOLDEN/$name.pages"
    printf 'UPDATE %s\n' "$name"
    continue
  fi

  for art in typ err pages; do
    g="$GOLDEN/$name.$art"; s="$stage/deck.typ.norm"
    [ "$art" = err ] && s="$stage/err.norm"
    [ "$art" = pages ] && s="$stage/.pages.tmp" && printf '%s\n' "$pages" > "$s"
    if ! diff -u "$g" "$s" > "$stage/diff.$art" 2>&1; then
      reason="${reason:+$reason; }golden .$art mismatch (see $stage/diff.$art)"
    fi
  done

  if [ -n "$reason" ]; then
    printf 'FAIL  %s — %s\n' "$name" "$reason"
    fail=$((fail + 1)); failed_names+=("$name")
  else
    printf 'ok    %s\n' "$name"
    pass=$((pass + 1))
  fi
done

rm -f "$WORK"/*/.pages.tmp 2>/dev/null || true
printf -- '----\n%d ok, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ] || printf 'failed: %s\n' "${failed_names[*]}"
[ "$fail" = 0 ]
