# ─── Herdr helpers ────────────────────────────────────────────

# Attach to the session named after the current folder (or $1), asking first
# if it already exists.
hr() {
    [[ -n "$HERDR_ENV" ]] && { echo "Already inside a Herdr session."; return 1; }

    local session_name="${1:-$(basename "$PWD")}" sessions_json
    sessions_json="$(herdr session list --json)" || return

    if print -r -- "$sessions_json" | jq -e --arg name "$session_name" \
        '.sessions[] | select(.name == $name)' >/dev/null; then
        printf 'Session "%s" exists. Attach/restore? [Y/n] ' "$session_name"
        local reply
        read -r reply
        case "$reply" in
            [nN]*) echo "Aborted."; return 1 ;;
            *)     herdr session attach "$session_name" ;;
        esac
    else
        herdr --session "$session_name"
    fi
}

# Fuzzy-pick a named session and attach to it (needs fzf and jq).
# Hides the built-in default session; with no sessions, falls back to hr.
hra() {
    [[ -n "$HERDR_ENV" ]] && { echo "Already inside a Herdr session."; return 1; }

    local sessions_json session_names s
    sessions_json="$(herdr session list --json)" || return
    session_names="$(print -r -- "$sessions_json" | \
        jq -r '.sessions[] | select(.default | not) | .name')" || return
    [[ -n "$session_names" ]] || { hr; return; }

    s="$(print -r -- "$session_names" | fzf --height 40% --reverse)" || return
    [[ -n "$s" ]] && herdr session attach "$s"
}

# Fuzzy-pick a running session and stop it (state kept, attachable later).
hrk() {
    local sessions_json session_names s
    sessions_json="$(herdr session list --json)" || return
    session_names="$(print -r -- "$sessions_json" | \
        jq -r '.sessions[] | select(.running) | .name')" || return
    [[ -n "$session_names" ]] || { echo "No running Herdr sessions."; return 1; }

    s="$(print -r -- "$session_names" | fzf --height 40% --reverse)" || return
    [[ -n "$s" ]] && herdr session stop "$s"
}

# Delete ONE stopped session by name (permanent).
hrdx() {
    [[ -n "$1" ]] || { echo "Usage: hrdx <name>"; return 1; }
    herdr session delete "$1"
}

# Delete all stopped named sessions (permanent); running sessions and the
# built-in default session are untouched.
hrd() {
    local sessions_json session_names
    sessions_json="$(herdr session list --json)" || return
    session_names="$(print -r -- "$sessions_json" | \
        jq -r '.sessions[] | select((.running | not) and (.default | not)) | .name')" || return
    [[ -n "$session_names" ]] || { echo "No stopped Herdr sessions."; return 0; }

    local -a sessions
    sessions=("${(@f)session_names}")

    local s rc=0
    for s in "${sessions[@]}"; do
        herdr session delete "$s" || rc=1
    done
    return $rc
}

# Help
hrh() {
    cat <<'EOF'
Herdr helpers
──────────────────────────────────────────────────────────────
hr [name]    Attach to the session named after the current folder
             (or [name]). If it exists, asks before attaching;
             otherwise creates it. Refuses to nest.

hra          Fuzzy-pick a session and attach to it. (fzf, jq)
             Hides "default". No sessions yet -> runs hr.

hrk          Fuzzy-pick a running session and STOP it. Its state is
             kept, so the session can be attached/restored later.

hrd          DELETE all stopped sessions (permanent). Running
             sessions and "default" are untouched.

hrdx <name>  DELETE one stopped session by name (permanent).

hrh          Show this help.
──────────────────────────────────────────────────────────────
stop   = terminate the server, keeping its persisted session state.
delete = remove a stopped named session permanently.
──────────────────────────────────────────────────────────────
EOF
}
