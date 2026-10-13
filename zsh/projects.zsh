# ─── Project jumping ──────────────────────────────────────────

# Fuzzy-pick a project under $GHCLONE_ROOT (the folders ghclone makes) and cd
# into it (needs fzf). Arguments prefill the search; a single match is taken
# without asking: p canary
p() {
    local root="${GHCLONE_ROOT:-$HOME/Development/github.com}" dir
    dir="$(cd "$root" && print -rl -- */*(N/) | \
        fzf --height 40% --reverse --select-1 --exit-0 --query "$*")"
    [[ -n "$dir" ]] || { [[ -n "$*" ]] && echo "No project matches \"$*\"."; return 1; }
    cd "$root/$dir"
}

# Jump to a project like p, then open its Herdr session like hr.
hp() {
    p "$@" && hr
}
