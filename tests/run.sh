#!/usr/bin/env bash
# Checks that the shell helpers load and work in bash and zsh, against stub
# commands (no git network, herdr, fzf or apt needed). Skips a shell that
# isn't installed.
#
#   bash tests/run.sh
#
# devbox has its own tests: bash devbox/tests/run.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0 fail=0

check_eq() {
    if [[ "$2" == "$3" ]]; then
        pass=$((pass + 1)); echo "  ok    $1"
    else
        fail=$((fail + 1)); echo "  FAIL  $1"; echo "        want: $2"; echo "        got:  $3"
    fi
}

# Stub bin: only the tools the helpers need, so a real codex, claude or apt
# is never run. Stubs append their arguments to $WORK/calls.
STUB="$WORK/bin"
mkdir -p "$STUB"
for t in sh cat grep sed sort find jq tee mktemp rm sleep python3 dirname basename head tr mkdir touch; do
    p="$(command -v "$t")" && ln -s "$p" "$STUB/$t"
done
stub() { printf '#!/bin/sh\n%s\n' "$2" >"$STUB/$1"; chmod +x "$STUB/$1"; }
stub git 'echo "git $*" >>"$WORK/calls"; [ "$1" = clone ] && mkdir -p "$3"; exit 0'
stub fzf 'q=""; while [ $# -gt 0 ]; do [ "$1" = --query ] && q="$2"; shift; done
cat >"$WORK/fzf-input"; grep -- "$q" "$WORK/fzf-input" | head -n 1'
stub sudo 'echo "sudo $*" >>"$WORK/calls"'
stub claude 'echo "claude $*" >>"$WORK/calls"
case "$*" in
    "plugin list --json") echo "[{\"id\":\"a@m\",\"scope\":\"user\"},{\"id\":\"b@m\",\"scope\":\"user\"},{\"id\":\"c@m\",\"scope\":\"project\"}]" ;;
    "plugin update --scope user b@m") exit 1 ;;
esac'
stub herdr 'echo "herdr $*" >>"$WORK/calls"
case "$*" in
    "session list --json") cat "$WORK/sessions.json" ;;
    "attach-flaky") [ -f "$WORK/flaked" ] && exit 0; touch "$WORK/flaked"; echo "live update in progress" >&2; exit 1 ;;
esac
exit 0'
# Echo server for _hr_api: replies to each request line with {"echo": <request>}.
cat >"$WORK/server.py" <<'PY'
import json, os, socket, sys
path = sys.argv[1]
s = socket.socket(socket.AF_UNIX); s.bind(path); s.listen()
open(path + ".ready", "w").close()
c, _ = s.accept()
line = c.makefile("rb").readline()
c.sendall(json.dumps({"echo": json.loads(line)}).encode() + b"\n")
c.close()
PY

# run SHELL SCRIPT: source local-config in SHELL with the stub PATH and run SCRIPT.
run() {
    local flag=-c
    [[ "$1" == zsh ]] && flag=-fc
    : >"$WORK/calls"
    env -i HOME="$WORK/home" PATH="$STUB" WORK="$WORK" GHCLONE_ROOT="$WORK/gh-$1" \
        "$SHELL_BIN" "$flag" 'source "$1/local-config.zsh" || exit 99; eval "$2"' _ "$ROOT" "$2" 2>&1
}

mkdir -p "$WORK/p/a/one" "$WORK/p/b/two" "$WORK/p/a/.git" "$WORK/p/.hidden/x"
touch "$WORK/p/b/file"

for sh in bash zsh; do
    SHELL_BIN="$(command -v "$sh")" || { echo "== $sh: not installed, skipped"; continue; }
    echo "== $sh"

    check_eq "loads every helper" "" "$(run "$sh" '
        for f in ghclone p hp gup gdone upall zl zla zlk zldx zlh hr hra hrk hru hrd hrdx hrh dv dvh; do
            type "$f" >/dev/null 2>&1 || echo "missing $f"
        done')"

    for c in "user/repo|https://github.com/user/repo.git|user/repo" \
             "https://github.com/a-b/c.d.git/tree/main?x#y|https://github.com/a-b/c.d.git|a-b/c.d" \
             "git@github.com:me/tool.git|git@github.com:me/tool.git|me/tool"; do
        IFS='|' read -r in url dir <<<"$c"
        check_eq "ghclone $in" "git clone $url $WORK/gh-$sh/$dir
$WORK/gh-$sh/$dir" "$(run "$sh" "ghclone '$in' >/dev/null && cat \"\$WORK/calls\" && pwd")"
    done
    check_eq "ghclone rejects junk" "Error: Could not parse GitHub URL: not a repo" "$(run "$sh" 'ghclone "not a repo"')"

    check_eq "p lists projects and cds" "a/one
b/two
$WORK/p/b/two" "$(run "$sh" 'GHCLONE_ROOT="$WORK/p"; p two && cat "$WORK/fzf-input" && pwd')"

    echo '{"sessions":[{"name":"run","running":true,"default":false},{"name":"old one","running":false,"default":false},{"name":"old2","running":false,"default":false},{"name":"default","running":false,"default":true}]}' >"$WORK/sessions.json"
    check_eq "hra prefills a multiword query" "herdr session list --json
herdr session attach old one" "$(run "$sh" 'hra old one && cat "$WORK/calls"')"
    check_eq "hra unmatched query does not attach" "rc=1
herdr session list --json" "$(run "$sh" 'hra missing; echo "rc=$?"; cat "$WORK/calls"')"
    check_eq "hrk unmatched query does not stop another session" "rc=1
herdr session list --json" "$(run "$sh" 'hrk old; echo "rc=$?"; cat "$WORK/calls"')"
    check_eq "hrk matching query stops the session" "herdr session list --json
herdr session stop run" "$(run "$sh" 'hrk run && cat "$WORK/calls"')"
    check_eq "hrd deletes stopped named sessions" "herdr session list --json
herdr session delete old one
herdr session delete old2" "$(run "$sh" 'hrd && cat "$WORK/calls"')"

    check_eq "_hr_attach keeps the attach command's status" "boom
rc=3" "$(run "$sh" '_hr_attach x sh -c "echo boom >&2; exit 3"; echo "rc=$?"')"
    rm -f "$WORK/flaked"
    check_eq "_hr_attach reconnects after a live handoff" "live update in progress
Herdr server was updated; reconnecting to s...
rc=0
herdr attach-flaky
herdr session attach s" "$(run "$sh" '_hr_attach s herdr attach-flaky; echo "rc=$?"; cat "$WORK/calls"')"

    sock="$WORK/hr.sock"
    rm -f "$sock" "$sock.ready"
    python3 "$WORK/server.py" "$sock" &
    for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -f "$sock.ready" ]] && break; sleep 0.2; done
    check_eq "_hr_api sends a request and prints the reply" '{"echo": {"id": "t"}}
missing socket: rc=1' "$(run "$sh" '_hr_api "$WORK/hr.sock" "{\"id\":\"t\"}"; _hr_api "$WORK/nope.sock" "{}" || echo "missing socket: rc=$?"')"
    wait

    rm -f "$STUB/herdr.off"; mv "$STUB/herdr" "$STUB/herdr.off"
    out="$(run "$sh" 'upall; echo "rc=$?"; cat "$WORK/calls"')"
    mv "$STUB/herdr.off" "$STUB/herdr"
    check_eq "upall runs each step and lists failures" "
==> apt

==> claude

==> claude plugin a@m

==> claude plugin b@m

Failed: claude plugin b@m
rc=1
sudo apt update
sudo apt upgrade -y
claude update
claude plugin list --json
claude plugin update --scope user a@m
claude plugin update --scope user b@m" "$(printf '%s\n' "$out" | sed $'s/\033\\[[0-9;]*m//g')"

    git_repo="$WORK/repo-$sh"
    command -v git >/dev/null && {
        git init -q -b master "$git_repo"
        git -C "$git_repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
        check_eq "_git_default_branch finds master" "master" \
            "$(cd "$git_repo" && PATH="$(dirname "$(command -v git)"):$PATH" "$SHELL_BIN" -c 'source "$1/zsh/git.zsh"; _git_default_branch' _ "$ROOT")"
    }
done

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
