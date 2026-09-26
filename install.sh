#!/usr/bin/env bash
# install.sh — делает команду `slides` доступной из CLI.
# Кладёт маленькую обёртку в ~/.local/bin (или ~/bin) — без прав root,
# работает на Linux, macOS и Windows (Git Bash).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLIDES="$SCRIPT_DIR/slides"

[ -x "$SLIDES" ] || chmod +x "$SLIDES"

# выбираем bin-каталог: первый существующий/создаваемый из списка
BIN_DIR="$HOME/.local/bin"
if [ -d "$HOME/bin" ] && ! [ -d "$HOME/.local/bin" ]; then
  BIN_DIR="$HOME/bin"
fi
mkdir -p "$BIN_DIR"

printf '#!/usr/bin/env bash\nexec "%s/slides" "$@"\n' "$SCRIPT_DIR" > "$BIN_DIR/slides"
chmod +x "$BIN_DIR/slides"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    cat <<EOF
Готово: обёртка создана в $BIN_DIR/slides

Каталог $BIN_DIR ещё не в PATH. Добавьте в ~/.bashrc строку:

  export PATH="$BIN_DIR:\$PATH"

и перезапустите терминал (или выполните её в текущей сессии).
EOF
    exit 0
    ;;
esac

echo "Готово: команда 'slides' установлена в $BIN_DIR"
echo "Проверка: slides help"
