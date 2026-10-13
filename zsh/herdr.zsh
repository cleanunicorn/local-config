# ─── Herdr helpers ────────────────────────────────────────────

# Run an attach command for session $1, and reattach whenever a live handoff
# (hru, herdr update --handoff) replaces the server under it. Other exits
# (detach, stop, another client taking over) end the loop as usual.
_hr_attach() {
    local session_name="$1" err rc started tries=0
    shift
    err="$(mktemp)" || return
    while true; do
        started=$SECONDS
        # stderr goes through tee so the reason stays visible and greppable.
        { "$@" 2>&1 1>&3 3>&- | tee "$err" >&2 } 3>&1
        rc=${pipestatus[1]}
        grep -q 'live update in progress' "$err" || break
        (( SECONDS - started > 10 )) && tries=0
        (( ++tries > 15 )) && { echo "Herdr handoff did not finish; run hr again."; break; }
        echo "Herdr server was updated; reconnecting to $session_name..."
        sleep 1
        set -- herdr session attach "$session_name"
    done
    rm -f "$err"
    return $rc
}

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
            *)     _hr_attach "$session_name" herdr session attach "$session_name" ;;
        esac
    else
        _hr_attach "$session_name" herdr --session "$session_name"
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
    [[ -n "$s" ]] && _hr_attach "$s" herdr session attach "$s"
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

# Send one JSON request to a Herdr server socket and print its reply line.
_hr_api() {
    local sock="$1" request="$2" timeout="${3:-5}" fd line rc
    zmodload zsh/net/socket || return
    zsocket "$sock" 2>/dev/null || return
    fd=$REPLY
    print -r -u $fd -- "$request"
    read -r -t "$timeout" -u $fd line
    rc=$?
    exec {fd}>&-
    (( rc == 0 )) && print -r -- "$line"
}

# Move running sessions (all, or the ones named) onto the installed Herdr
# binary by live handoff: panes and agents keep running, nothing restarts.
hru() {
    [[ -n "$HERDR_ENV" ]] && { echo "Run hru outside Herdr (detach first)."; return 1; }

    local client_json sessions_json rows exe version protocol
    client_json="$(herdr status client --json)" || return
    exe="$(print -r -- "$client_json" | jq -r .binary)"
    version="$(print -r -- "$client_json" | jq -r .version)"
    protocol="$(print -r -- "$client_json" | jq -r .protocol)"
    sessions_json="$(herdr session list --json)" || return
    rows="$(print -r -- "$sessions_json" | jq -r --args '.sessions[]
        | select(.running)
        | select(($ARGS.positional | length) == 0
                 or (.name as $n | $ARGS.positional | any(. == $n)))
        | [.name, .socket_path] | @tsv' "$@")" || return
    [[ -n "$rows" ]] || { echo "No matching running Herdr sessions."; return 1; }

    local -a targets
    local row name sock pong server_version
    for row in "${(@f)rows}"; do
        name="${row%%$'\t'*}" sock="${row#*$'\t'}"
        pong="$(_hr_api "$sock" '{"id":"hru","method":"ping","params":{}}')" || {
            echo "  $name: server not answering, skipped"; continue; }
        server_version="$(print -r -- "$pong" | jq -r .result.version)"
        [[ "$server_version" == "$version" ]] && continue
        if ! print -r -- "$pong" | jq -e '.result.capabilities.live_handoff' >/dev/null; then
            echo "  $name: v$server_version can't hand off; stop and reattach it instead"
            continue
        fi
        echo "  $name  v$server_version -> v$version"
        targets+=("$row")
    done
    (( ${#targets} )) || { echo "Running sessions are already on v$version."; return 0; }

    printf 'Hand off these sessions to v%s? Panes keep running. [y/N] ' "$version"
    local reply
    read -r reply
    [[ "$reply" == [yY]* ]] || { echo "Aborted."; return 1; }

    local request reply_json i rc=0
    request="$(jq -nc --arg exe "$exe" --arg v "$version" --argjson p "$protocol" \
        '{id: "hru", method: "server.live_handoff",
          params: {import_exe: $exe, expected_version: $v, expected_protocol: $p}}')"
    for row in "${targets[@]}"; do
        name="${row%%$'\t'*}" sock="${row#*$'\t'}"
        echo "$name: handing off..."
        reply_json="$(_hr_api "$sock" "$request" 240)" || {
            echo "$name: no reply to the handoff request"; rc=1; continue; }
        if print -r -- "$reply_json" | jq -e '.error' >/dev/null; then
            echo "$name: handoff refused: $(print -r -- "$reply_json" | jq -c .error)"
            rc=1; continue
        fi
        # The old server exits and the new one takes over the socket.
        for i in {1..30}; do
            sleep 1
            pong="$(_hr_api "$sock" '{"id":"hru","method":"ping","params":{}}')" || continue
            [[ "$(print -r -- "$pong" | jq -r .result.version)" == "$version" ]] && break
            pong=""
        done
        if [[ -n "$pong" ]]; then
            echo "$name: now on v$version"
        else
            echo "$name: not confirmed after 30s; check \`herdr session list\`"
            rc=1
        fi
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
             otherwise creates it. Refuses to nest. Reconnects
             by itself when hru updates the server under it.

hra          Fuzzy-pick a session and attach to it. (fzf, jq)
             Hides "default". No sessions yet -> runs hr.
             Reconnects by itself like hr.

hrk          Fuzzy-pick a running session and STOP it. Its state is
             kept, so the session can be attached/restored later.

hru [name…]  Move running sessions (all, or the named ones) onto
             the installed herdr version by live handoff. Panes
             and agents keep running. Run after `herdr update`.

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
