#!/bin/sh
# Install shell-helpers: clone the repo (if needed) and source it from ~/.zshrc.
#
#   ./install.sh                     from a checkout: use that checkout
#   curl -fsSL <raw-url>/install.sh | sh
#                                    clone into $SHELL_HELPERS_DIR
#                                    (default ~/.local/share/shell-helpers)
#
# Safe to run more than once.
set -eu

REPO_URL="https://github.com/cleanunicorn/shell-helpers.git"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -n "$script_dir" ] && [ -f "$script_dir/shell-helpers.zsh" ]; then
    dir="$script_dir"
else
    dir="${SHELL_HELPERS_DIR:-$HOME/.local/share/shell-helpers}"
    if [ -d "$dir/.git" ]; then
        echo "Updating $dir"
        git -C "$dir" pull --ff-only
    else
        echo "Cloning into $dir"
        git clone "$REPO_URL" "$dir"
    fi
fi

if [ -f "$ZSHRC" ] && grep -q 'shell-helpers\.zsh' "$ZSHRC"; then
    echo "$ZSHRC already sources shell-helpers; leaving it alone."
else
    printf '\n# shell-helpers — %s\nsource "%s/shell-helpers.zsh"\n' \
        "$REPO_URL" "$dir" >> "$ZSHRC"
    echo "Added shell-helpers to $ZSHRC"
fi

command -v zsh >/dev/null 2>&1 || echo "Note: zsh is not installed; these helpers need zsh."
echo "Done. Open a new shell, or run: source \"$dir/shell-helpers.zsh\""
