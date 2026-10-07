# shell-helpers — entry point. Source this from ~/.zshrc:
#
#   source /path/to/shell-helpers/shell-helpers.zsh
#
# Loads every module in zsh/. To add helpers, drop a new .zsh file there.

SHELL_HELPERS_DIR="${${(%):-%x}:A:h}"

for _sh_module in "$SHELL_HELPERS_DIR"/zsh/*.zsh(N); do
    source "$_sh_module"
done
unset _sh_module
