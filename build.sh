#!/usr/bin/env bash
# Build slides:  ./build.sh <deck.md> [out.pdf|out-dir]
# Requires: pandoc, typst. No hardcoded absolute paths (everything is derived
# from this script's location, so the theme is portable).
#
# Outputs <name>.pdf next to the SOURCE markdown file (the intermediate
# .typ goes to a temp dir; see below).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn() { printf 'slides: ВНИМАНИЕ: %s\n' "$*" >&2; WARN_COUNT=$((WARN_COUNT + 1)); }
err()  { printf 'slides: ОШИБКА: %s\n' "$*" >&2; }
WARN_COUNT=0

usage() {
  sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

SRC_ARG="${1:-}"
OUT_ARG="${2:-}"

if [ -z "$SRC_ARG" ] || [ "$SRC_ARG" = "-h" ] || [ "$SRC_ARG" = "--help" ]; then
  [ $# -gt 0 ] || echo "slides: ОШИБКА: не указан файл деки" >&2
  usage >&2
  exit 1
fi
if [ $# -gt 2 ]; then
  err "слишком много аргументов (ожидается дека и, возможно, выходной файл/каталог)"
  usage >&2
  exit 1
fi

# Resolve the source to an absolute path (relative to the caller's cwd —
# captured BEFORE the cd into the theme dir below).
case "$SRC_ARG" in
  /*) SRC_ABS="$SRC_ARG" ;;
  *)  SRC_ABS="$(pwd)/$SRC_ARG" ;;
esac
if [ ! -f "$SRC_ABS" ]; then
  err "файл деки не найден: $SRC_ARG"
  exit 1
fi

FINAL_PDF=""
if [ -n "$OUT_ARG" ]; then
  case "$OUT_ARG" in
    /*) OUT_ABS="$OUT_ARG" ;;
    *)  OUT_ABS="$(pwd)/$OUT_ARG" ;;
  esac
  FINAL_PDF="$OUT_ABS"
fi

# Work inside the theme directory so --font-path and cwd-relative asset
# references resolve consistently; outputs still go next to the source.
cd "$SCRIPT_DIR"

# --- dependency + version gates ------------------------------------------------
# Presence is fatal; version mismatch only warns (newer versions usually
# still work — the user should know the tested range, not be blocked).
require_tools() {
  local pv tv
  command -v pandoc >/dev/null 2>&1 \
    || { err "pandoc не установлен — см. README «Установка»"; exit 1; }
  command -v typst >/dev/null 2>&1 \
    || { err "typst не установлен — см. README «Установка»"; exit 1; }
  pv="$(pandoc --version 2>/dev/null | head -1 | awk '{print $2}')"
  case "$pv" in
    3.*) ;;
    *)  warn "pandoc ${pv:-неизвестной версии} — конвейер тестировался с pandoc 3.x" ;;
  esac
  tv="$(typst --version 2>/dev/null | awk '{print $2}')"
  case "$tv" in
    0.14.*|0.15.*) ;;
    *)  warn "typst ${tv:-неизвестной версии} — тема тестировалась с typst 0.14–0.15" ;;
  esac
}
require_tools

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

# --- input normalization + frontmatter extraction ---------------------------
# One awk pass turns any user deck into a CANONICAL stream, so downstream
# (pandoc + the Lua filter) never sees the byte-level surprises that used to
# break real decks:
#   * UTF-8 BOM on line 1            -> stripped (Windows editors add it)
#   * CRLF line endings              -> stripped to LF (Windows editors)
#   * blank line(s) before the       -> tolerated: frontmatter is recognized
#     leading `---`                     after leading blanks too
#   * a leading `---` block that is  -> stays verbatim body text (a `---`
#     NOT YAML-shaped                     separator, not metadata)
#   * `---` directly after a text    -> a blank line is inserted first, so a
#     line (setext-heading trap)         line can never silently become a
#                                        slide title; `---` ALWAYS means
#                                        "slide break" (fence-aware)
# After normalization the leading YAML-shaped block is lifted into
# $FM_FILE and the pandoc call below runs with -yaml_metadata_block, so a
# mid-deck `---` can never abort the build or swallow slide text.
#
# The body copy must live NEXT TO THE SOURCE: the Lua filter resolves
# relative image paths against the directory of its input file, so a temp
# elsewhere (e.g. $WORK_DIR in /tmp) would break deck-relative images.
DECK_MD="$(mktemp "$SRC_DIR/.slides-deck.XXXXXX")"
FM_FILE="$WORK_DIR/frontmatter.yaml"
awk -v fmfile="$FM_FILE" '
  BEGIN { mode = "head"; fence = ""; prevblank = 1 }
  function is_rule(l)  { return l ~ /^(---|\.\.\.)[ \t]*$/ }
  function is_fence(l) { return l ~ /^[ \t]?[ \t]?[ \t]?(```|~~~)/ }
  # body printer: tracks fences, inserts the setext guard blank line
  function emit(l,   fc) {
    if (is_fence(l)) {
      fc = l; sub(/^[ \t]?[ \t]?[ \t]?/, "", fc); fc = substr(fc, 1, 1)
      if (fence == "") fence = fc
      else if (fence == fc) fence = ""
    }
    if (fence == "" && l ~ /^---[ \t]*$/ && !prevblank) print ""
    print l
    prevblank = (l ~ /^[ \t]*$/)
  }
  # does the candidate block (pnd[1..pn-1]) look like YAML key/value data?
  function looks_yaml(   i, l, keys) {
    keys = 0
    for (i = 1; i < pn; i++) {
      l = pnd[i]
      if (l ~ /^[ \t]*$/) continue
      if (l ~ /^#/) continue                              # YAML comment
      if (l ~ /^[A-Za-z_][A-Za-z0-9_.-]*:( |$)/) { keys++; continue }
      if (l ~ /^-[ \t]/ || l == "-") continue             # sequence item
      if (l ~ /^[ \t]/) continue                          # folded/indented value
      return 0
    }
    return keys > 0
  }
  {
    line = $0
    sub(/\r$/, "", line)
    if (NR == 1) sub(/^\xef\xbb\xbf/, "", line)

    if (mode == "head") {
      if (line ~ /^[ \t]*$/) next                         # skip leading blanks
      if (line ~ /^---[ \t]*$/) { mode = "pending"; pnd[0] = line; pn = 1; next }
      mode = "body"; emit(line); next
    }
    if (mode == "pending") {
      if (is_rule(line)) {                                # closer found
        if (looks_yaml()) {
          for (i = 1; i < pn; i++) print pnd[i] > fmfile
          closed = 1
        } else {                                          # not YAML: plain body
          emit(pnd[0]); for (i = 1; i < pn; i++) emit(pnd[i]); emit(line)
        }
        mode = "body"
      } else pnd[pn++] = line
      next
    }
    emit(line)
  }
  END {
    if (mode == "pending") { emit(pnd[0]); for (i = 1; i < pn; i++) emit(pnd[i]) }
  }
' "$SRC_ABS" > "$DECK_MD"
FM_ARGS=()
if [ -s "$FM_FILE" ]; then
  FM_ARGS=(--metadata-file "$FM_FILE")
fi

# --- frontmatter validation ---------------------------------------------------
# Typos in keys or values used to be swallowed silently. Warn loudly (never
# fatal): the user sees exactly what the theme did not understand.
warn_fm() { warn "frontmatter: $*"; }
if [ -s "$FM_FILE" ]; then
  # accept the kebab-case alias, canonical key is dark_theme (template.typ)
  if grep -qE '^dark-theme:' "$FM_FILE" && ! grep -qE '^dark_theme:' "$FM_FILE"; then
    sed -i 's/^dark-theme:/dark_theme:/' "$FM_FILE"
    warn_fm "ключ dark-theme принят как dark_theme"
  fi
  FM_KNOWN="title subtitle author date institution accent-color focus-accent title-font body-font cover-image toc progress-bar dark_theme aspect-ratio lang"
  while IFS= read -r raw; do
    key="${raw%%:*}"
    val="${raw#*:}"; val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    val="${val#\"}"; val="${val%\"}"
    known=0
    for k in $FM_KNOWN; do [ "$k" = "$key" ] && known=1 && break; done
    if [ "$known" = 0 ]; then
      warn_fm "неизвестный ключ «$key» — проигнорирован (поддерживаются: $FM_KNOWN)"
      continue
    fi
    case "$key" in
      accent-color|focus-accent)
        printf '%s' "$val" | grep -qE '^#?[0-9a-fA-F]{3}$|^#?[0-9a-fA-F]{6}$' \
          || warn_fm "$key «$val» — не HEX-цвет (например 26619C); используется цвет по умолчанию" ;;
      aspect-ratio)
        printf '%s' "$val" | grep -qE '^[0-9]+(\.[0-9]+)?-[0-9]+(\.[0-9]+)?$' \
          || warn_fm "aspect-ratio «$val» — ожидался формат W-H (например 16-9); используется 16-9" ;;
      toc|progress-bar|dark_theme)
        printf '%s' "$val" | grep -qiE '^(true|false|yes|no|on|off|1|0)$' \
          || warn_fm "$key «$val» — ожидалось true/false; значение не применится" ;;
    esac
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_.-]*:' "$FM_FILE" || true)
fi

KEEP_WORK=0
trap 'rm -f "$DECK_MD"; if [ "$KEEP_WORK" = 0 ]; then rm -rf "$WORK_DIR"; fi' EXIT

# --- deck font availability -----------------------------------------------------
# The theme falls back silently inside typst; this makes the substitution
# visible ONCE, up front. typst then repeats its own "unknown font family"
# warning at every usage site — those duplicates are filtered out of the
# compile output below (only for families already reported here).
FONT_MISS_LIST=""
check_deck_fonts() {
  command -v typst >/dev/null 2>&1 || return 0
  [ -d "$SCRIPT_DIR/fonts" ] || return 0
  [ -s "$FM_FILE" ] || return 0
  local avail fam
  avail="$(typst fonts --font-path "$SCRIPT_DIR/fonts" 2>/dev/null || true)"
  [ -n "$avail" ] || return 0
  while IFS= read -r fam; do
    [ -n "$fam" ] || continue
    printf '%s\n' "$avail" | grep -qixF "$fam" || {
      warn "шрифт «$fam» (frontmatter) не найден ни в fonts/, ни в системе — тема подставит запасной"
      FONT_MISS_LIST+="$fam"$'\n'
    }
  done < <(sed -nE 's/^[[:space:]]*(title-font|body-font):[[:space:]]*//p' "$FM_FILE" \
    | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' | sort -u)
}
check_deck_fonts

FONT_ARGS=()
if [ -d "$SCRIPT_DIR/fonts" ]; then
  FONT_ARGS=(--font-path "$SCRIPT_DIR/fonts")
fi

# --- image resolution: probe -> verify -> manifest ---------------------------
# image-probe.lua walks the real AST (code-fence-proof, wikilink-aware) and
# prints every image src; bash then resolves each reference against the
# filesystem and sniffs the real format from magic bytes. Bash (not Lua)
# does all file I/O: on Windows, Lua's io.open inside native pandoc.exe
# goes through the ANSI code page and cannot see non-ASCII (UTF-8) paths.
# Results travel to the main Lua filter via --metadata argv — the one
# Unicode-safe channel into pandoc — joined with \037 (records) and \036
# (fields): control characters cannot occur in filenames.

pct_decode() { # full %XX decoding, incl. UTF-8 byte sequences
  local s=$1
  s=${s//\\/\\\\}
  printf '%b' "$(printf '%s' "$s" | sed -E 's/%([0-9A-Fa-f]{2})/\\x\1/g')"
}

sniff_fmt() { # magic bytes -> png|jpg|gif|webp|svg (typst format names)
  local hex8
  hex8="$(head -c 16 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  case "$hex8" in
    89504e470d0a1a0a*)           echo png ;;
    ffd8ff*)                     echo jpg ;;
    474946383761*|474946383961*) echo gif ;;
    52494646????????57454250*)   echo webp ;;
    *) if head -c 256 "$1" 2>/dev/null \
         | grep -qiE '^[[:space:]]*(<\?xml|<svg)'; then echo svg; fi ;;
  esac
}

IMG_EXTS="png jpg jpeg gif webp svg"
R_path=""; R_fmt=""; R_why=""

classify_file() { # $1 = existing path -> R_path/R_fmt or R_why
  if [ ! -s "$1" ]; then R_why="файл пуст (0 байт)"; return 1; fi
  R_fmt="$(sniff_fmt "$1")"
  if [ -z "$R_fmt" ]; then
    R_why="не изображение (поддерживаются png, jpg, gif, webp, svg): $1"
    return 1
  fi
  R_path="$1"; return 0
}

resolve_ref() { # $1 = src -> R_path/R_fmt on success, R_why on failure
  local ref="$1" dec p f c base hit
  case "$ref" in
    http:*|https:*) R_why="сетевая ссылка — сохраните файл рядом с декой"; return 1 ;;
  esac
  dec="$(pct_decode "$ref")"
  local -a cands=()
  for p in "$ref" "$dec"; do
    p="${p//\\//}"
    case "$p" in
      /*|[A-Za-z]:/*) cands+=("$p") ;;
      *)              cands+=("$SRC_DIR/$p") ;;
    esac
  done
  # Obsidian idiom 1: references without extension (![[photo]] -> photo.png)
  base="${ref##*/}"
  if [ "$base" != "*.*" ]; then
    for f in $IMG_EXTS; do
      cands+=("$SRC_DIR/$ref.$f")
      if [ "$dec" != "$ref" ]; then cands+=("$SRC_DIR/$dec.$f"); fi
    done
  fi
  for c in ${cands[@]+"${cands[@]}"}; do
    if [ -f "$c" ]; then
      if classify_file "$c"; then return 0; fi
    fi
  done
  # Obsidian idiom 2: "shortest path" links omit directories (![[photo]] for
  # assets/photo.png) — search the deck's subtree as a last resort.
  if [ -n "$base" ]; then
    local -a pats=()
    pats+=(-name "$base")
    for f in $IMG_EXTS; do pats+=(-o -name "$base.$f"); done
    hit="$(LC_ALL=C find "$SRC_DIR" -type f \( "${pats[@]}" \) 2>/dev/null \
      | LC_ALL=C sort | head -n 1 || true)"
    if [ -n "$hit" ]; then
      if classify_file "$hit"; then return 0; fi
    fi
  fi
  R_why="файл не найден"; return 1
}

to_typst_virtual() { # abs fs path -> path valid inside the compile --root
  local p="$1"
  if [ "$IS_WIN" = 1 ]; then
    p="$(cygpath -m "$p")"
    case "$p" in
      [A-Za-z]:/*) p="/${p:3}" ;;
    esac
  fi
  printf '%s' "$p"
}

# Reader spec (both pandoc passes MUST stay identical):
#   -yaml_metadata_block  frontmatter is lifted by the awk normalizer and fed
#                         via --metadata-file; a mid-deck `---` block must
#                         never abort the build or swallow slide text
#   -raw_tex              LaTeX insertions are not typst; drop them
#   -blank_before_header  `## H` right after a text line (or after `---`) is
#                         a real slide heading, not paragraph text
#   -multiline_tables     a dashed `---` border pair must NEVER be read as a
#   -simple_tables        table (it is a slide split); pipe tables stay on
#   +wikilinks_title_after_pipe   Obsidian `![[pic.png]]` embeds become real
#                         images the filter can lay out
PROBE="$(pandoc "$DECK_MD" \
  --from "markdown-yaml_metadata_block-raw_tex-blank_before_header-multiline_tables-simple_tables+wikilinks_title_after_pipe" \
  --to plain \
  --lua-filter "$SCRIPT_DIR/image-probe.lua" \
  "${FM_ARGS[@]}" || true)"

MAP_FILE="$WORK_DIR/imgmap.txt"
MISS_FILE="$WORK_DIR/imgmiss.txt"
: > "$MAP_FILE"; : > "$MISS_FILE"
while IFS= read -r line; do
  case "$line" in IMG:*|COVER:*) ref="${line#*:}" ;; *) continue ;; esac
  [ -n "$ref" ] || continue
  if resolve_ref "$ref"; then
    printf '%s\036%s\036%s\n' "$ref" "$(to_typst_virtual "$R_path")" "$R_fmt" >> "$MAP_FILE"
  else
    printf '%s\036%s\n' "$ref" "$R_why" >> "$MISS_FILE"
  fi
done <<< "$PROBE"

MAP_ARGS=()
if [ -s "$MAP_FILE" ]; then
  MAP_ARGS=(--metadata "image-map=$(paste -sd $'\037' "$MAP_FILE")")
fi
MISS_ARGS=()
if [ -s "$MISS_FILE" ]; then
  MISS_ARGS=(--metadata "missing-images=$(paste -sd $'\037' "$MISS_FILE")")
fi

# Extension tweaks:
#   -yaml_metadata_block               `---` is ALWAYS a slide separator:
#                                     pandoc would otherwise also read
#                                     mid-document `---` blocks as YAML
#                                     metadata (frontmatter travels via
#                                     --metadata-file instead)
#   -raw_tex                           keep `\word` sequences as literal text
#                                     instead of silently dropping raw TeX
#   +wikilinks_title_after_pipe        Obsidian `![[pic.png]]` embeds become
#                                     real images the filter can lay out
PAN_ERR="$WORK_DIR/pandoc.err"
if ! pandoc "$DECK_MD" \
    "${MAP_ARGS[@]}" \
    "${MISS_ARGS[@]}" \
    --from "markdown-yaml_metadata_block-raw_tex-blank_before_header-multiline_tables-simple_tables+wikilinks_title_after_pipe" \
    --to typst \
    --standalone \
    --template "$SCRIPT_DIR/template.typ" \
    --lua-filter "$SCRIPT_DIR/theme-filters.lua" \
    "${FM_ARGS[@]}" \
    --output "$TYP" 2> "$PAN_ERR"; then
  KEEP_WORK=1
  sed 's/^/  /' "$PAN_ERR" >&2
  err "pandoc не смог разобрать деку (подробности выше). Чаще всего это сломанный frontmatter: проверьте отступы и кавычки в ---блоке в начале файла."
  err "промежуточные файлы сохранены: $WORK_DIR"
  exit 1
fi
[ -s "$PAN_ERR" ] && cat "$PAN_ERR" >&2

# The filter emits root-relative image paths and the staged .typ sits next
# to its theme copy, so root covers everything (Unix: "/", Windows: "E:/").
TYP_ERR="$WORK_DIR/typst.err"
if ! typst compile --root "$ROOT" "${FONT_ARGS[@]}" "$TYP" "$PDF" 2> "$TYP_ERR"; then
  KEEP_WORK=1
  sed 's/^/  /' "$TYP_ERR" >&2
  err "typst не смог собрать PDF (подробности выше). Если ошибка указывает на строку .typ — скорее всего, в деке есть блок \`\`\`{=typst} с опечаткой."
  err "сгенерированный Typst сохранён: $TYP"
  err "ручная пересборка для отладки: typst compile --root '$ROOT' '$TYP'"
  exit 1
fi
# drop typst's duplicate "unknown font family" blocks for families we already
# reported once above (typst warns at every usage site)
if [ -n "$FONT_MISS_LIST" ]; then
  awk -v pats="$FONT_MISS_LIST" '
    BEGIN {
      n = split(pats, a, "\n")
      for (i = 1; i <= n; i++) if (a[i] != "") skip[tolower(a[i])] = 1
    }
    /^warning: unknown font family: / {
      fam = tolower($0); sub(/^warning: unknown font family: /, "", fam); gsub(/\\/, "", fam)
      if (skip[fam]) { infont = 1; next }
    }
    infont {
      if ($0 ~ /^[[:space:]]*$/) { infont = 0; print ""; next }
      next
    }
    { print }
  ' "$TYP_ERR" > "$TYP_ERR.f" && mv "$TYP_ERR.f" "$TYP_ERR"
fi
[ -s "$TYP_ERR" ] && cat "$TYP_ERR" >&2

# warnings emitted by the Lua filter arrive via the pandoc/typst captures.
# NB: pure awk, not `grep -c | awk` — under pipefail a matchless grep would
# fail the whole substitution and set -e would kill the build silently.
LUA_WARNS="$(awk '/^slides: ВНИМАНИЕ/{n++} END{print n+0}' "$PAN_ERR" "$TYP_ERR" 2>/dev/null)" || true
# NB: a plain `X=$((sum))` exits 1 under set -e when the sum is 0 (bash
# treats a zero-valued arithmetic assignment as failure) — hence `|| true`.
WARN_COUNT=$((WARN_COUNT + LUA_WARNS)) || true

if [ -n "$FINAL_PDF" ]; then
  if [ "$FINAL_PDF" != "$PDF" ]; then
    if [ -d "$FINAL_PDF" ]; then FINAL_PDF="$FINAL_PDF/$BASE.pdf"; fi
    mkdir -p "$(dirname "$FINAL_PDF")"
    cp "$PDF" "$FINAL_PDF"
  fi
else
  FINAL_PDF="$PDF"
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  echo "Готово: $FINAL_PDF (предупреждений: $WARN_COUNT — детали выше)"
else
  echo "Готово: $FINAL_PDF"
fi
