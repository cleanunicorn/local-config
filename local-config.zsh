# local-config — entry point. Source this from ~/.zshrc:
#
#   source /path/to/local-config/local-config.zsh
#
# Loads every module in zsh/. To add helpers, drop a new .zsh file there.

LOCAL_CONFIG_DIR="${${(%):-%x}:A:h}"

for _lc_module in "$LOCAL_CONFIG_DIR"/zsh/*.zsh(N); do
    source "$_lc_module"
done
unset _lc_module
