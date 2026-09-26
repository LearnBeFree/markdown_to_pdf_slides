#!/usr/bin/env bash
# watch.sh — следит за декой и пересобирает PDF при изменениях.
#
# Использование:
#   ./watch.sh <deck.md> [выходной.pdf | выходной-каталог]
#
# - Опрашивает исходный файл и все картинки, на которые он ссылается
#   (одинаковая работа на Linux, macOS и Windows Git Bash — inotify не нужен).
# - При запуске: подтягивает обновления темы из git (если настроен remote)
#   и проверяет доступность нужных шрифтов.
# - Останов: Ctrl+C.  Интервал опроса: переменная WATCH_INTERVAL (по умолч. 0.7с).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ARG="${1:-}"
INTERVAL="${WATCH_INTERVAL:-0.7}"

usage() {
  sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}
case "$SRC_ARG" in
  -h|--help|"") usage ;;
esac

case "$SRC_ARG" in
  /*) SRC_ABS="$SRC_ARG" ;;
  *)  SRC_ABS="$(pwd)/$SRC_ARG" ;;
esac
if [ ! -f "$SRC_ABS" ]; then
  echo "Source not found: $SRC_ARG" >&2
  exit 1
fi
SRC_DIR="$(dirname "$SRC_ABS")"
BASE="$(basename "$SRC_ABS")"
BASE="${BASE%.*}"

if [ "${2:-}" != "" ]; then
  case "$2" in
    /*) OUT_ABS="$2" ;;
    *)  OUT_ABS="$(pwd)/$2" ;;
  esac
  [ -d "$OUT_ABS" ] && OUT_ABS="$OUT_ABS/$BASE.pdf"
else
  OUT_ABS="$SRC_DIR/$BASE.pdf"
fi
BUILT_PDF="$SRC_DIR/$BASE.pdf"

# ---- вывод -----------------------------------------------------------------
if [ -t 1 ]; then
  C_DIM=$'\e[2m'; C_B=$'\e[1m'; C_G=$'\e[32m'; C_R=$'\e[31m'
  C_Y=$'\e[33m'; C_C=$'\e[36m'; C_0=$'\e[0m'
else
  C_DIM=""; C_B=""; C_G=""; C_R=""; C_Y=""; C_C=""; C_0=""
fi
ts() { date +%H:%M:%S; }
say()  { printf '%s %s\n' "${C_DIM}[$(ts)]${C_0}" "$*"; }
ok()   { printf '%s %s\n' "${C_DIM}[$(ts)]${C_0}" "${C_G}✓${C_0} $*"; }
warn() { printf '%s %s\n' "${C_DIM}[$(ts)]${C_0}" "${C_Y}⚠${C_0} $*"; }
err()  { printf '%s %s\n' "${C_DIM}[$(ts)]${C_0}" "${C_R}✗${C_0} $*"; }

TMPLOG="$(mktemp -d)"
cleanup() { rm -rf "$TMPLOG"; }
trap cleanup EXIT
trap 'printf "\n"; say "остановлен"; exit 0' INT TERM

# ---- проверка обновлений темы из git ---------------------------------------
git_pull_updates() {
  command -v git >/dev/null 2>&1 || { warn "git не найден — проверка обновлений пропущена"; return; }
  git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1 \
    || { warn "это не git-репозиторий — проверка обновлений пропущена"; return; }
  local remote_url
  remote_url="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)"
  if [ -z "$remote_url" ]; then
    warn "git remote 'origin' не настроен — проверка обновлений пропущена"
    return
  fi
  say "проверяю обновления темы (${remote_url})…"
  local remote_sha
  remote_sha="$(git_wrap 15 git -C "$SCRIPT_DIR" ls-remote origin HEAD 2>/dev/null | cut -f1 || true)"
  if [ -z "$remote_sha" ]; then
    warn "не удалось связаться с remote — работаю с локальной версией"
    return
  fi
  local local_sha
  local_sha="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")"
  if [ "$remote_sha" = "$local_sha" ]; then
    ok "тема актуальна (${local_sha:0:7})"
  else
    say "на remote есть новые коммиты — подтягиваю…"
    if git -C "$SCRIPT_DIR" pull --ff-only --autostash --quiet >/dev/null 2>&1; then
      ok "тема обновлена до $(git -C "$SCRIPT_DIR" rev-parse HEAD | cut -c1-7)" \
        && warn "запустите вотчер заново, чтобы подхватить новые скрипты"
    else
      err "не удалось обновиться — выполните вручную: git -C '$SCRIPT_DIR' pull"
    fi
  fi
}

# запуск команды с таймаутом, если timeout доступен
git_wrap() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  else
    "$@"
  fi
}

# ---- проверка шрифтов ------------------------------------------------------
check_fonts() {
  local available
  available="$(typst fonts --font-path "$SCRIPT_DIR/fonts" 2>/dev/null || true)"
  if [ -z "$available" ]; then
    warn "не удалось получить список шрифтов (typst fonts) — продолжаю"
    return
  fi
  local missing=() f
  # шрифты, поставляемые с темой
  for f in Oswald Philosopher; do
    printf '%s\n' "$available" | grep -qixF "$f" || missing+=("$f")
  done
  # шрифты, которые дека просит во frontmatter (title-font / body-font)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$available" | grep -qixF "$f" || missing+=("$f")
  done < <(grep -iE '^[[:space:]]*(title-font|body-font):' "$SRC_ABS" 2>/dev/null \
    | sed -E 's/^[^:]*:[[:space:]]*//; s/"//g' | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "шрифты на месте (Oswald, Philosopher + шрифты деки)"
  else
    warn "шрифты не найдены: ${missing[*]}"
    warn "тема сама подставит запасные (Liberation/системные) — сборка не сломается"
  fi
}

# ---- что наблюдать: исходник + все локальные картинки деки ------------------
deck_assets() {
  {
    # ![подпись](путь) — включая <путь с пробелами> "title"
    grep -oE '!\[[^]]*\]\([^)]+\)' "$SRC_ABS" 2>/dev/null \
      | sed -E 's/^!\[[^]]*\]\(//; s/\)$//; s/^<//; s/>.*$//; s/[[:space:]]*".*$//'
    # Obsidian-вставки ![[p.png]] и ссылки [[p|alias]] / [[p]]
    grep -oE '!?\[\[[^]]+\]\]' "$SRC_ABS" 2>/dev/null \
      | sed -E 's/^!?\[\[//; s/\]\]$//; s/\|.*$//'
    # обложка из frontmatter
    grep -iE '^[[:space:]]*cover-image:' "$SRC_ABS" 2>/dev/null \
      | sed -E 's/^[^:]*:[[:space:]]*//; s/"//g'
  } | while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) p="$SRC_DIR/$p" ;; esac
    p="$(printf '%s' "$p" | sed 's/%20/ /g; s/%5B/[/g; s/%5D/]/g')"
    [ -f "$p" ] && printf '%s\n' "$p"
  done | sort -u
}

signature() {
  {
    cksum "$SRC_ABS" 2>/dev/null || true
    deck_assets | while IFS= read -r f; do
      printf '%s %s %s\n' "$f" \
        "$(date -r "$f" +%s 2>/dev/null || echo 0)" \
        "$(wc -c < "$f" 2>/dev/null || echo 0)"
    done
  } | cksum | cut -d' ' -f1
  return 0
}

# ---- сборка -----------------------------------------------------------------
build_once() {
  local t0 dt pages=""
  t0=$(date +%s)
  if "$SCRIPT_DIR/build.sh" "$SRC_ABS" >"$TMPLOG/out" 2>"$TMPLOG/err"; then
    dt=$(( $(date +%s) - t0 ))
    command -v pdfinfo >/dev/null 2>&1 \
      && pages="$(pdfinfo "$BUILT_PDF" 2>/dev/null | awk '/^Pages/{print ", "$2" стр."}')"
    if [ "$OUT_ABS" != "$BUILT_PDF" ]; then
      mkdir -p "$(dirname "$OUT_ABS")" 2>/dev/null || true
      if cp "$BUILT_PDF" "$OUT_ABS" 2>/dev/null; then
        ok "успешно собрано (${dt}с${pages}) → $OUT_ABS"
      else
        err "сборка ок, но не удалось скопировать в $OUT_ABS"
      fi
    else
      ok "успешно собрано (${dt}с${pages}) → $OUT_ABS"
    fi
  else
    err "сборка не удалась:"
    sed 's/^/    /' "$TMPLOG/err" | sed -n '1,40p'
    [ -s "$TMPLOG/out" ] && sed 's/^/    /' "$TMPLOG/out" | sed -n '1,10p'
  fi
}

# ---- запуск -----------------------------------------------------------------
printf '%s\n' "${C_C}${C_B}── slides watcher ────────────────────────────────${C_0}"
say  "дека:    $SRC_ABS"
say  "выход:   $OUT_ABS"
git_pull_updates
check_fonts
printf '%s\n' "${C_DIM}── слежу за изменениями (Ctrl+C — остановить) ──${C_0}"

build_once
last="$(signature)"

while true; do
  sleep "$INTERVAL"
  cur="$(signature || echo sig-error)"
  if [ "$cur" != "$last" ]; then
    say "обнаружены изменения — пересобираю…"
    # ждём, пока запись файла успокоится (атомарные сохранения пишут в 2 приёма)
    prev="$cur"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 0.3
      s2="$(signature || echo "$prev")"
      [ "$s2" = "$prev" ] && break
      prev="$s2"
    done
    build_once
    last="$(signature || echo "$cur")"
  fi
done
