# ─── Zellij helpers ──────────────────────────────────────────────

# Attach to session named after current folder (or $1), asking first if it exists
zl() {
    [[ -n "$ZELLIJ" ]] && { echo "Already inside a Zellij session."; return 1; }

    local session_name="${1:-$(basename "$PWD")}"

    if zellij list-sessions -s 2>/dev/null | grep -qx "$session_name"; then
        printf 'Session "%s" exists. Attach/resurrect? [Y/n] ' "$session_name"
        local reply
        read -r reply
        case "$reply" in
            [nN]*) echo "Aborted."; return 1 ;;
            *)     zellij attach "$session_name" ;;
        esac
    else
        zellij --session "$session_name"
    fi
}

# Fuzzy-pick a session and attach (needs fzf)
zla() {
    local s
    s="$(zellij list-sessions -s 2>/dev/null | fzf --height 40% --reverse)" || return
    [[ -n "$s" ]] && zellij attach "$s"
}

# Fuzzy-pick a session and kill it (state kept, resurrectable)
zlk() {
    local s
    s="$(zellij list-sessions -s 2>/dev/null | fzf --height 40% --reverse)" || return
    [[ -n "$s" ]] && zellij kill-session "$s"
}

# Delete ONE exited session by name (permanent)
zldx() { zellij delete-session "$1"; }

alias zld='zellij delete-all-sessions --yes'     # delete exited sessions only, no prompt

# Help
zlh() {
    cat <<'EOF'
Zellij helpers
──────────────────────────────────────────────────────────────
zl [name]    Attach to the session named after the current folder
             (or [name]). If it exists, asks before attaching;
             otherwise creates it. Refuses to nest.
             e.g.  zl          -> session "my-project"
                   zl scratch  -> session "scratch"

zla          Fuzzy-pick a session and attach to it. (fzf)

zlk          Fuzzy-pick a session and KILL it. Terminates it but
             keeps its serialized state -> resurrectable later.

zld          DELETE all exited sessions (permanent). Does not
             touch running sessions.

zldx <name>  DELETE one exited session by name (permanent).

zlh          Show this help.
──────────────────────────────────────────────────────────────
kill  = terminate, state kept, can be resurrected.
delete = state removed from cache, gone for good.

Never add -f/--force to delete-session or delete-all-sessions:
it kills RUNNING sessions before deleting them. No undo.
──────────────────────────────────────────────────────────────
EOF
}
