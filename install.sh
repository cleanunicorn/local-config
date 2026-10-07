#!/bin/sh
# Install from a checkout of this repo:
#
#   git clone https://github.com/cleanunicorn/local-config.git
#   cd local-config && ./install.sh [--dry-run]
#
# 1. Symlinks every file under home/ to the same path under $HOME
#    (home/.config/herdr/config.toml -> ~/.config/herdr/config.toml).
#    An existing file in the way is moved aside to <name>.bak-<timestamp>.
# 2. Adds one line to ~/.zshrc that sources local-config.zsh.
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

zshrc="${ZDOTDIR:-$HOME}/.zshrc"
if [ -f "$zshrc" ] && grep -q 'local-config\.zsh' "$zshrc"; then
    echo "$zshrc already sources local-config.zsh"
else
    echo "Adding local-config.zsh to $zshrc"
    if [ "$dry_run" -eq 0 ]; then
        printf '\n# local-config\n[ -f "%s/local-config.zsh" ] && source "%s/local-config.zsh"\n' \
            "$repo" "$repo" >> "$zshrc"
    fi
fi

echo "Done. Open a new shell to pick up the helpers."
