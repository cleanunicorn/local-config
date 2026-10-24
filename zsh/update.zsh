# ─── Update everything ────────────────────────────────────────

# One upall step: print its name, run it, and add the name to the caller's
# $failed if it fails.
_upall_step() {
    local name="$1"
    shift
    printf '\n\033[1m==> %s\033[0m\n' "$name"
    "$@" || failed+=("$name")
}

_upall_has() { command -v "$1" >/dev/null 2>&1; }

# Update the system packages and the dev tools that update themselves, then
# move running Herdr sessions onto the new version without restarting them.
# Tools that aren't installed are skipped. Every step runs even if an earlier
# one fails, and the failures are listed at the end.
upall() {
    [[ -n "$HERDR_ENV" ]] && { echo "Run upall outside Herdr (detach first)."; return 1; }

    local -a failed
    local id

    _upall_step "apt" sh -c 'sudo apt update && sudo apt upgrade -y'
    _upall_has claude && {
        _upall_step "claude" claude update
        while IFS= read -r -u 3 id; do
            [[ -n "$id" ]] && _upall_step "claude plugin $id" claude plugin update --scope user "$id"
        done 3<<<"$(claude plugin list --json 2>/dev/null | \
                jq -r '.[] | select(.scope == "user") | .id' | sort -u)"
    }
    _upall_has codex    && _upall_step "codex" codex update
    _upall_has opencode && _upall_step "opencode" opencode upgrade
    _upall_has pi       && _upall_step "pi" pi update --all
    _upall_has cctop    && _upall_step "cctop" cctop upgrade
    _upall_has uv       && _upall_step "uv tools" uv tool upgrade --all
    _upall_has herdr    && {
        _upall_step "herdr" herdr update --handoff
        # Catches sessions left on an older server by an earlier plain update.
        herdr session list --json | jq -e '[.sessions[] | select(.running)] | length > 0' >/dev/null &&
            _upall_step "herdr sessions" hru
    }

    if (( ${#failed[@]} )); then
        local list
        list="$(printf '%s, ' "${failed[@]}")"
        printf '\n\033[1;31mFailed:\033[0m %s\n' "${list%, }"
        return 1
    fi
    printf '\n\033[1;32mEverything is up to date.\033[0m\n'
}
