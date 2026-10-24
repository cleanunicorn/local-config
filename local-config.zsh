# local-config — entry point. Source this from ~/.zshrc or ~/.bashrc:
#
#   source /path/to/local-config/local-config.zsh
#
# Loads every module in zsh/. The modules work in zsh and bash. To add
# helpers, drop a new .zsh file there.

if [[ -n "${BASH_VERSION:-}" ]]; then
    LOCAL_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    LOCAL_CONFIG_DIR="${${(%):-%x}:A:h}"
fi

for _lc_module in "$LOCAL_CONFIG_DIR"/zsh/*.zsh; do
    [[ -f "$_lc_module" ]] && source "$_lc_module"
done
unset _lc_module
