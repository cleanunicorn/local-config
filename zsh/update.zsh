# ─── Update everything ────────────────────────────────────────

# Update the system packages and the dev tools that update themselves, then
# move running Herdr sessions onto the new version without restarting them.
# Tools that aren't installed are skipped. Every step runs even if an earlier
# one fails, and the failures are listed at the end.
upall() {
    [[ -n "$HERDR_ENV" ]] && { echo "Run upall outside Herdr (detach first)."; return 1; }

    local -a failed
    local id

    _upall_step() {
        local name="$1"
        shift
        print -P "\n%B==> $name%b"
        "$@" || failed+=("$name")
    }

    _upall_step "apt" zsh -c 'sudo apt update && sudo apt upgrade -y'
    (( $+commands[claude] )) && {
        _upall_step "claude" claude update
        for id in ${(f)"$(claude plugin list --json 2>/dev/null | \
                jq -r '.[] | select(.scope == "user") | .id' | sort -u)"}; do
            _upall_step "claude plugin $id" claude plugin update --scope user "$id"
        done
    }
    (( $+commands[codex] ))    && _upall_step "codex" codex update
    (( $+commands[opencode] )) && _upall_step "opencode" opencode upgrade
    (( $+commands[pi] ))       && _upall_step "pi" pi update --all
    (( $+commands[cctop] ))    && _upall_step "cctop" cctop upgrade
    (( $+commands[uv] ))       && _upall_step "uv tools" uv tool upgrade --all
    (( $+commands[herdr] ))    && {
        _upall_step "herdr" herdr update --handoff
        # Catches sessions left on an older server by an earlier plain update.
        herdr session list --json | jq -e '[.sessions[] | select(.running)] | length > 0' >/dev/null &&
            _upall_step "herdr sessions" hru
    }

    unfunction _upall_step
    if (( ${#failed} )); then
        print -P "\n%B%F{red}Failed:%f%b ${(j:, :)failed}"
        return 1
    fi
    print -P "\n%B%F{green}Everything is up to date.%f%b"
}
