#!/bin/sh
# Install from a checkout of this repo:
#
#   git clone https://github.com/cleanunicorn/local-config.git
#   cd local-config && ./install.sh [--dry-run]
#
# 1. Symlinks every file under home/ to the same path under $HOME
#    (home/.config/herdr/config.toml -> ~/.config/herdr/config.toml).
#    An existing file in the way is moved aside to <name>.bak-<timestamp>.
# 2. Adds one line to ~/.zshrc and ~/.bashrc that sources local-config.zsh
#    (for each shell that is installed or already has an rc file).
#
# Safe to run again: links that are already correct are left alone.
set -eu

dry_run=0
case "${1:-}" in
    --dry-run|-n) dry_run=1 ;;
    "") ;;
    *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

repo="$(cd "$(dirname "$0")" && pwd)"
[ -f "$repo/local-config.zsh" ] || { echo "Run this from a checkout of the repo." >&2; exit 1; }
stamp="$(date +%Y%m%d-%H%M%S)"

run() {
    if [ "$dry_run" -eq 1 ]; then echo "  would: $*"; else "$@"; fi
}

echo "Linking files from $repo/home into $HOME"
cd "$repo/home"
find . -type f | sed 's|^\./||' | sort | while IFS= read -r rel; do
    src="$repo/home/$rel"
    dst="$HOME/$rel"

    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        echo "  ok      ~/$rel"
        continue
    fi

    run mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        echo "  backup  ~/$rel -> ~/$rel.bak-$stamp"
        run mv "$dst" "$dst.bak-$stamp"
    fi
    echo "  link    ~/$rel"
    run ln -s "$src" "$dst"
done

add_source_line() {
    rc="$1"
    if [ -f "$rc" ] && grep -q 'local-config\.zsh' "$rc"; then
        echo "$rc already sources local-config.zsh"
    else
        echo "Adding local-config.zsh to $rc"
        if [ "$dry_run" -eq 0 ]; then
            printf '\n# local-config\n[ -f "%s/local-config.zsh" ] && source "%s/local-config.zsh"\n' \
                "$repo" "$repo" >> "$rc"
        fi
    fi
}

zshrc="${ZDOTDIR:-$HOME}/.zshrc"
bashrc="$HOME/.bashrc"
if command -v zsh >/dev/null 2>&1 || [ -f "$zshrc" ]; then add_source_line "$zshrc"; fi
if command -v bash >/dev/null 2>&1 || [ -f "$bashrc" ]; then add_source_line "$bashrc"; fi

echo "Done. Open a new shell to pick up the helpers."
