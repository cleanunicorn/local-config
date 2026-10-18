#!/usr/bin/env bash
# Devbox gate: syntax checks for every shell file, then an isolated Docker
# integration test of devbox.zsh against a separate image.
#
#   bash tests/run.sh                  full run (builds devbox-test-<pid>:latest)
#   bash tests/run.sh --syntax-only    syntax checks only
#   DEVBOX_TEST_KEEP_IMAGE=1 …         keep the test image afterwards
#   DEVBOX_TEST_ALLOW_SKIP=1 …         accept skipped checks (e.g. no local
#                                      alpine/socat image; it is never pulled)
#
# Isolation: image devbox-test-<pid>, network devnet-test-<pid>, throwaway project
# folders /tmp/devbox-test.* (devbox names devtmp_devbox-test.*). Never builds
# or tags devbox:*, never touches the user's devboxes, volumes or devnet, and
# removes everything it created on exit. Exits non-zero on any failure.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0 SKIP=0

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; }
skip() { SKIP=$((SKIP + 1)); printf '  skip  %s\n' "$1"; }
# check DESC CMD... — passes when CMD exits 0.
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
# check_eq DESC EXPECTED ACTUAL
check_eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }
# check_has DESC NEEDLE HAYSTACK
check_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "no '$2' in: $(printf '%s' "$3" | tr '\n' ' ' | cut -c1-300)"; fi; }
section() { printf '\n== %s\n' "$1"; }

# A skip is a failure unless DEVBOX_TEST_ALLOW_SKIP=1: a check that did not
# run must not look like a pass.
finish() {
    printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
    (( FAIL == 0 )) || return 1
    if (( SKIP > 0 )) && [[ "${DEVBOX_TEST_ALLOW_SKIP:-0}" != 1 ]]; then
        echo "Skipped checks count as failures (DEVBOX_TEST_ALLOW_SKIP=1 to accept them)."
        return 1
    fi
}

# ---------------------------------------------------------------- syntax
section "syntax"
check "zsh -n devbox.zsh"               zsh -n "$ROOT/devbox.zsh"
check "bash -n devbox.zsh"              bash -n "$ROOT/devbox.zsh"
check "sh -n bin/docker"                sh -n "$ROOT/bin/docker"
check "sh -n bin/devbox-compose-link"   sh -n "$ROOT/bin/devbox-compose-link"
check "bash -n tests/run.sh"            bash -n "$ROOT/tests/run.sh"
check "sources in bash"  bash -c 'source "$1/devbox.zsh" && cd /tmp && [[ "$(_get_container_name)" == devtmp ]]' _ "$ROOT"
check "sources in zsh"   zsh -fc 'source "$1/devbox.zsh" && cd /tmp && [[ "$(_get_container_name)" == devtmp ]]' _ "$ROOT"

if [[ "${1:-}" == "--syntax-only" ]]; then finish; exit; fi

# ---------------------------------------------------------------- isolation
export DEVBOX_DIR="$ROOT"
export DEVBOX_IMAGE="devbox-test-$$"
IMG="${DEVBOX_IMAGE}:latest"
export DEVBOX_NET="devnet-test-$$"
TEST_PREFIX="devtmp_devbox-test."
TMPBASE=/tmp
PROJECTS=() NAMES=()

die() { echo "ABORT: $*" >&2; FAIL=$((FAIL + 1)); exit 1; }

# The user's real devboxes and volumes: must be identical before and after.
real_state() {
    docker volume ls --format '{{.Name}}' | grep '^devhome' | sort
    docker ps -a --filter label=devbox.role=main --format '{{.Names}} {{.ID}}' | grep -v "^${TEST_PREFIX}" | sort
    docker ps -a --filter label=devbox.role=port --format '{{.Names}} {{.ID}}' | grep -v "^${TEST_PREFIX}" | sort
    docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep '^devbox:' | sort
}

# Refuses any name outside the test prefix — the last line of defence before rm.
is_test_name() { [[ "$1" == ${TEST_PREFIX}* ]]; }

cleanup() {
    local n c v
    for n in "${NAMES[@]}"; do
        is_test_name "$n" || { echo "cleanup: refusing '$n'" >&2; continue; }
        for c in $(docker ps -a --format '{{.Names}}' | awk -v p="$n" 'index($0, p) == 1'); do
            is_test_name "$c" && docker rm -f "$c" >/dev/null 2>&1
        done
        for v in home claude history; do
            docker volume rm "${n}-${v}" >/dev/null 2>&1
        done
    done
    [[ "$DEVBOX_NET" == devnet-test-* ]] && docker network rm "$DEVBOX_NET" >/dev/null 2>&1
    [[ "${DEVBOX_TEST_KEEP_IMAGE:-0}" == 1 ]] || docker rmi "$IMG" >/dev/null 2>&1
    local p
    for p in "${PROJECTS[@]}"; do [[ "$p" == "$TMPBASE"/devbox-test.* ]] && rm -rf "$p"; done
    [[ -n "${BUILD_LOG:-}" ]] && rm -f "$BUILD_LOG"
    if [[ -n "${REAL_BEFORE:-}" ]]; then
        if [[ "$(real_state)" == "$REAL_BEFORE" ]]; then
            ok "user's devbox images, devboxes, sidecars and devhome volumes unchanged"
        else
            bad "user's devbox images, devboxes, sidecars and devhome volumes unchanged" \
                "$(diff <(printf '%s\n' "$REAL_BEFORE") <(real_state) | tr '\n' ' ')"
        fi
    fi
    finish
}

# new_project VAR — make a throwaway project folder; sets VAR to its path and
# VAR_N (e.g. P1_N) to its devbox name.
new_project() {
    local p n
    p="$(mktemp -d "$TMPBASE/devbox-test.XXXXXX")" || die "mktemp"
    PROJECTS+=("$p")
    n="$(cd "$p" && bash -c 'source "$1/devbox.zsh"; _get_container_name' _ "$ROOT")"
    is_test_name "$n" || die "project name '$n' is outside the test prefix"
    NAMES+=("$n")
    printf -v "$1" '%s' "$p"
    printf -v "${1}_N" '%s' "$n"
}

# dbx DIR CMD — run devbox.zsh functions in DIR under bash; dbz the same in zsh.
# CMD is one string: an extra word would be silently dropped, so misuse aborts
# the whole run (it is often called inside $(…), where a counter can't reach).
exec 3>&2   # the run's stderr, reachable from inside $(… 2>&1)
misuse() { echo "ABORT: $1: pass the command as one string: ${*:2}" >&3; kill -TERM $$; exit 99; }
dbx() { (( $# == 2 )) || misuse dbx "$@"
        bash -c 'source "$DEVBOX_DIR/devbox.zsh"; cd "$1" || exit 99; eval "$2"' _ "$1" "$2"; }
dbz() { (( $# == 2 )) || misuse dbz "$@"
        zsh -fc 'source "$DEVBOX_DIR/devbox.zsh"; cd "$1" || exit 99; eval "$2"' _ "$1" "$2"; }

cid() { docker inspect -f '{{.Id}}' "$1" 2>/dev/null; }
in_box() { local n="$1"; shift; docker exec "$n" "$@"; }
vol_exists() { docker volume inspect "$1" >/dev/null 2>&1; }
label_docker() { docker inspect -f '{{index .Config.Labels "devbox.docker"}}' "$1" 2>/dev/null; }

[[ "$DEVBOX_IMAGE" == devbox-test-* ]] || die "DEVBOX_IMAGE must be devbox-test-<pid>"
command -v docker >/dev/null || die "docker not found"
docker info >/dev/null 2>&1 || die "docker daemon not reachable"

REAL_BEFORE="$(real_state)"
trap 'cleanup; exit $?' EXIT
trap 'FAIL=$((FAIL + 1)); echo "ABORT: interrupted" >&2; exit 130' INT TERM

section "build $IMG"
BUILD_LOG="$(mktemp "$TMPBASE/devbox-test-build.XXXXXX.log")"
build_args=()
[[ -S /var/run/docker.sock ]] && build_args=(--build-arg "DOCKER_GID=$(stat -c %g /var/run/docker.sock)")
if docker build "${build_args[@]}" -t "$IMG" "$ROOT" >"$BUILD_LOG" 2>&1; then
    ok "image built"
else
    tail -30 "$BUILD_LOG" >&2
    die "docker build failed (see output above)"
fi

new_project P1

# ---------------------------------------------------------------- create + AC10 smoke
section "create, --docker, compose-link (AC10)"
out="$(dbx "$P1" devbox_recreate 2>&1)"; rc=$?
check_eq "devbox_recreate creates a missing devbox" 0 "$rc"
check "devbox is running" bash -c '[[ "$(docker inspect -f "{{.State.Running}}" "$1")" == true ]]' _ "$P1_N"
check_eq "created without docker access" "" "$(label_docker "$P1_N")"

out="$(dbx "$P1" 'devbox_recreate --docker' 2>&1)"; rc=$?
check_eq "devbox_recreate --docker" 0 "$rc"
check_eq "--docker sets label devbox.docker=1" 1 "$(label_docker "$P1_N")"
check_has "--docker sets COMPOSE_PROJECT_NAME" "COMPOSE_PROJECT_NAME=" \
    "$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$P1_N")"
check_eq "docker inside is the compose wrapper" /usr/local/bin/docker "$(in_box "$P1_N" sh -c 'command -v docker' 2>&1)"
check "docker inside reaches the host daemon" in_box "$P1_N" docker version
check "devbox-compose-link runs" in_box "$P1_N" devbox-compose-link
dbx "$P1" devbox_recreate >/dev/null 2>&1
check_eq "plain devbox_recreate keeps docker access" 1 "$(label_docker "$P1_N")"
dbx "$P1" 'devbox_recreate --no-docker' >/dev/null 2>&1
check_eq "devbox_recreate --no-docker drops it" "" "$(label_docker "$P1_N")"

section "port forwards (AC10)"
if docker image inspect alpine/socat >/dev/null 2>&1; then
    hp=""
    for _ in $(seq 1 50); do
        p=$((39000 + RANDOM % 900))
        ss -ltnH "sport = :$p" 2>/dev/null | grep -q . || { hp=$p; break; }
    done
    echo "hello-devbox" > "$P1/hello.txt"
    serve() { docker exec -d -w /workspace "$P1_N" python3 -m http.server 8765 --bind 0.0.0.0 >/dev/null; }
    fetch() { local i; for i in $(seq 1 40); do curl -fsS "http://127.0.0.1:$hp/hello.txt" 2>/dev/null && return 0; sleep 0.25; done; return 1; }
    serve
    out="$(dbx "$P1" "devbox_port 8765 $hp" 2>&1)"
    check_has "devbox_port prints the URL" "http://localhost:$hp" "$out"
    check_eq "forward answers through the sidecar" hello-devbox "$(fetch)"
    check_has "devbox_ports lists it" "localhost:$hp" "$(dbx "$P1" devbox_ports 2>&1)"
    dbx "$P1" devbox_recreate >/dev/null 2>&1
    serve
    check_eq "forward still answers after recreate" hello-devbox "$(fetch)"
    out="$(dbx "$P1" "devbox_unport $hp" 2>&1)"
    check_has "devbox_unport removes it" "Removed forward" "$out"
    check "sidecar is gone" bash -c '! docker inspect "$1" >/dev/null 2>&1' _ "${P1_N}-p${hp}"
else
    skip "alpine/socat not present locally (not pulled)"
fi

# ---------------------------------------------------------------- AC7
section "devbox_tmp (AC7)"
new_project P2
cmd="source $(printf '%q' "$ROOT/devbox.zsh"); cd $(printf '%q' "$P2") && devbox_tmp"
printf 'touch /workspace/ran; exit\n' | timeout 180 script -qec "bash -c $(printf '%q' "$cmd")" /dev/null >/dev/null 2>&1
check "devbox_tmp ran a shell in the project" test -e "$P2/ran"
check_eq "devbox_tmp container removed on exit" "" \
    "$(docker ps -a --format '{{.Names}}' | awk -v p="${P2_N}-tmp-" 'index($0, p) == 1')"
check_eq "devbox_tmp created no volume" "" \
    "$(docker volume ls --format '{{.Name}}' | awk -v p="${P2_N}" 'index($0, p) == 1')"

# ---------------------------------------------------------------- AC3
section "history config comes from /etc/bash.bashrc (AC3)"
check_eq "image's ~/.bashrc has no history settings" 0 "$(in_box "$P1_N" grep -c 'history -a' /home/dev/.bashrc)"
in_box "$P1_N" sh -c 'printf "# stub: a home from before the image change\n" > /home/dev/.bashrc'
out="$(in_box "$P1_N" bash -ic 'shopt -q histappend && echo HISTAPPEND; echo "PC=$PROMPT_COMMAND"; echo "HF=$HISTFILE"' 2>/dev/null)"
check_has "interactive bash has histappend without ~/.bashrc help" HISTAPPEND "$out"
check_has "interactive bash appends history each prompt" "PC=history -a" "$out"
check_has "HISTFILE points into ~/.history" "HF=/home/dev/.history/bash_history" "$out"

# ---------------------------------------------------------------- AC2
section "new home volume is filled from the image (AC2)"
home_mount() { docker inspect -f '{{range .Mounts}}{{if eq .Destination "/home/dev"}}{{.Type}}:{{.Name}}{{end}}{{end}}' "$1"; }
check_eq "/home/dev is the volume <name>-home" "volume:${P1_N}-home" "$(home_mount "$P1_N")"
check "no legacy -claude/-history volumes are created" bash -c '! docker volume inspect "$1-claude" >/dev/null 2>&1 && ! docker volume inspect "$1-history" >/dev/null 2>&1' _ "$P1_N"
check "claude is runnable from the home volume" in_box "$P1_N" claude --version
check_eq "home files owned by dev (uid 1000)" "1000 1000 1000 1000" \
    "$(in_box "$P1_N" stat -c %u /home/dev /home/dev/.local/bin/claude /home/dev/.claude /home/dev/.history | tr '\n' ' ' | sed 's/ $//')"

# ---------------------------------------------------------------- AC1 + AC3 across a recreate
section "home survives devbox_recreate (AC1, AC3)"
marker="marker-$$-$RANDOM"
in_box "$P1_N" sh -c 'mkdir -p ~/.config/gh && echo "github.com: {user: devbox-test}" > ~/.config/gh/hosts.yml && git config --global user.name devbox-test'
printf 'echo %s\nexit\n' "$marker" | docker exec -i "$P1_N" bash -i >/dev/null 2>&1
id_before="$(cid "$P1_N")"
out="$(dbx "$P1" devbox_recreate 2>&1)"; rc=$?
check_eq "devbox_recreate" 0 "$rc"
check_has "recreate says the home volume is kept" "home volume and port forwards are kept" "$out"
check "container was really replaced" test "$(cid "$P1_N")" != "$id_before"
check_eq "~/.config/gh/hosts.yml survived" "github.com: {user: devbox-test}" "$(in_box "$P1_N" cat /home/dev/.config/gh/hosts.yml 2>&1)"
check_eq "~/.gitconfig survived" devbox-test "$(in_box "$P1_N" git config --global user.name 2>&1)"
check_eq "a pre-change ~/.bashrc survived untouched" "# stub: a home from before the image change" "$(in_box "$P1_N" cat /home/dev/.bashrc 2>&1)"
check_has "bash history survived (HISTFILE in the home)" "echo $marker" "$(in_box "$P1_N" cat /home/dev/.history/bash_history 2>&1)"

# ---------------------------------------------------------------- AC6
section "legacy -claude/-history volumes are copied into a new home (AC6)"
new_project P3
docker run --rm --network none -v "${P3_N}-claude:/home/dev/.claude" -v "${P3_N}-history:/home/dev/.history" "$IMG" \
    sh -c 'echo legacy-login > ~/.claude/.credentials.json && echo legacy-cmd > ~/.history/bash_history' >/dev/null
out="$(dbx "$P3" devbox_recreate 2>&1)"; rc=$?
check_eq "first create with legacy volumes" 0 "$rc"
check_has "says it copied them" "Copied this project's Claude login and history" "$out"
check_eq "Claude login copied" legacy-login "$(in_box "$P3_N" cat /home/dev/.claude/.credentials.json 2>&1)"
check_has "history copied" legacy-cmd "$(in_box "$P3_N" cat /home/dev/.history/bash_history 2>&1)"
check_eq "copied files owned by dev" "1000 1000" \
    "$(in_box "$P3_N" stat -c %u /home/dev/.claude/.credentials.json /home/dev/.history/bash_history | tr '\n' ' ' | sed 's/ $//')"
check "image content still there (claude runs)" in_box "$P3_N" claude --version
check "legacy volumes left in place" bash -c 'docker volume inspect "$1-claude" "$1-history" >/dev/null 2>&1' _ "$P3_N"
check_eq "legacy volumes unchanged" legacy-login \
    "$(docker run --rm --network none -v "${P3_N}-claude:/c:ro" "$IMG" cat /c/.credentials.json 2>&1)"
in_box "$P3_N" sh -c 'echo new-login > /home/dev/.claude/.credentials.json'
out="$(dbx "$P3" devbox_recreate 2>&1)"
check "no second copy on a later recreate" bash -c '[[ "$1" != *Copied* ]]' _ "$out"
check_eq "later changes kept over legacy data" new-login "$(in_box "$P3_N" cat /home/dev/.claude/.credentials.json 2>&1)"

new_project P4
docker run --rm --network none -v "${P4_N}-history:/home/dev/.history" "$IMG" \
    sh -c 'echo only-history > ~/.history/bash_history' >/dev/null
cmd="source $(printf '%q' "$ROOT/devbox.zsh"); cd $(printf '%q' "$P4") && devbox_shell"
printf 'exit\n' | timeout 180 script -qec "bash -c $(printf '%q' "$cmd")" /dev/null >/dev/null 2>&1
check_eq "devbox_shell creates with the home volume" "volume:${P4_N}-home" "$(home_mount "$P4_N" 2>&1)"
check_has "only -history present: it is copied" only-history "$(in_box "$P4_N" cat /home/dev/.history/bash_history 2>&1)"
check "missing -claude is not created" bash -c '! docker volume inspect "$1-claude" >/dev/null 2>&1' _ "$P4_N"

new_project P5
docker run -d --name "$P5_N" --network "$DEVBOX_NET" --label devbox.role=main --label "devbox.project=$P5_N" \
    -v "$P5":/workspace -v "${P5_N}-claude":/home/dev/.claude -v "${P5_N}-history":/home/dev/.history \
    "$IMG" >/dev/null
in_box "$P5_N" sh -c 'echo old-box-login > /home/dev/.claude/.credentials.json'
out="$(dbx "$P5" devbox_recreate 2>&1)"; rc=$?
check_eq "recreating a pre-home-volume devbox" 0 "$rc"
check_has "it warns that container-only home files are not carried over" "are not carried over" "$out"
check_eq "its Claude login moved into the home volume" old-box-login "$(in_box "$P5_N" cat /home/dev/.claude/.credentials.json 2>&1)"
out="$(dbx "$P5" devbox_recreate 2>&1)"
check "no warning once the home volume exists" bash -c '[[ "$1" != *"not carried over"* ]]' _ "$out"

# The same migration under zsh (the user's main shell): array code paths differ.
new_project P7
docker run --rm --network none -v "${P7_N}-claude:/home/dev/.claude" -v "${P7_N}-history:/home/dev/.history" "$IMG" \
    sh -c 'echo p7-login > ~/.claude/.credentials.json && echo p7-cmd > ~/.history/bash_history' >/dev/null
out="$(dbz "$P7" devbox_recreate 2>&1)"; rc=$?
check_eq "zsh: first create with legacy volumes" 0 "$rc"
check_has "zsh: says it copied them" "Copied this project's Claude login and history" "$out"
check_eq "zsh: Claude login copied" p7-login "$(in_box "$P7_N" cat /home/dev/.claude/.credentials.json 2>&1)"
check_has "zsh: history copied" p7-cmd "$(in_box "$P7_N" cat /home/dev/.history/bash_history 2>&1)"
check_eq "zsh: copied files owned by dev" "1000 1000" \
    "$(in_box "$P7_N" stat -c %u /home/dev/.claude/.credentials.json /home/dev/.history/bash_history | tr '\n' ' ' | sed 's/ $//')"
check "zsh: legacy volumes left in place" bash -c 'docker volume inspect "$1-claude" "$1-history" >/dev/null 2>&1' _ "$P7_N"

# A failing legacy copy must leave the old devbox and its data as they were.
new_project P6
docker run --rm --network none -v "${P6_N}-claude:/home/dev/.claude" -v "${P6_N}-history:/home/dev/.history" "$IMG" \
    sh -c 'echo p6-login > ~/.claude/.credentials.json && echo p6-cmd > ~/.history/bash_history' >/dev/null
docker run -d --name "$P6_N" --network "$DEVBOX_NET" --label devbox.role=main --label "devbox.project=$P6_N" \
    -v "$P6":/workspace -v "${P6_N}-claude":/home/dev/.claude -v "${P6_N}-history":/home/dev/.history \
    "$IMG" >/dev/null
id_before="$(cid "$P6_N")"
fail_copy='docker() { if [[ "$*" == *"--user 0"* ]]; then return 1; fi; command docker "$@"; }'
out="$(dbx "$P6" "$fail_copy; devbox_recreate" 2>&1)"; rc=$?
check "failed legacy copy: recreate fails" test "$rc" -ne 0
check_has "failed legacy copy: says nothing changed" "nothing was changed" "$out"
check_eq "failed legacy copy: old container kept" "$id_before" "$(cid "$P6_N")"
check "failed legacy copy: no half-filled home left" bash -c '! docker volume inspect "$1-home" >/dev/null 2>&1' _ "$P6_N"
check_eq "failed legacy copy: legacy login intact" p6-login "$(in_box "$P6_N" cat /home/dev/.claude/.credentials.json 2>&1)"
out="$(dbx "$P6" devbox_recreate 2>&1)"; rc=$?
check_eq "after a failed copy, the next recreate works" 0 "$rc"
check_has "…and copies the legacy volumes again" "Copied this project's Claude login and history" "$out"
check_eq "…so the old login arrives" p6-login "$(in_box "$P6_N" cat /home/dev/.claude/.credentials.json 2>&1)"
new_project P8
docker run --rm --network none -v "${P8_N}-claude:/home/dev/.claude" "$IMG" \
    sh -c 'echo p8-login > ~/.claude/.credentials.json' >/dev/null
out="$(dbx "$P8" "$fail_copy; devbox_recreate" 2>&1)"; rc=$?
check "failed legacy copy, no devbox yet: create fails" test "$rc" -ne 0
check "…no container is left" bash -c '! docker inspect "$1" >/dev/null 2>&1' _ "$P8_N"
check "…and no half-filled home" bash -c '! docker volume inspect "$1-home" >/dev/null 2>&1' _ "$P8_N"

# ---------------------------------------------------------------- AC4
section "devbox_recreate --fresh-home (AC4)"
in_box "$P3_N" sh -c 'echo keep-me > /home/dev/sentinel'
id_before="$(cid "$P3_N")"
for answer in n "" no; do
    out="$(printf '%s\n' "$answer" | dbx "$P3" 'devbox_recreate --fresh-home' 2>&1)"; rc=$?
    check "answer '${answer}' declines (non-zero)" test "$rc" -ne 0
done
check_has "it asks y/N first" "[y/N]" "$out"
out="$(dbx "$P3" 'devbox_recreate --fresh-home' </dev/null 2>&1)"; rc=$?
check "no input at all (EOF) declines" test "$rc" -ne 0
check_has "EOF: says nothing changed" "nothing changed" "$out"
check_has "EOF: points to --yes" "add --yes to confirm" "$out"
out="$(dbz "$P3" 'devbox_recreate --fresh-home' </dev/null 2>&1)"; rc=$?
check "zsh: EOF declines" test "$rc" -ne 0
check_has "declining says nothing changed" "nothing changed" "$out"
check_eq "declining keeps the container" "$id_before" "$(cid "$P3_N")"
check_eq "declining keeps the home" keep-me "$(in_box "$P3_N" cat /home/dev/sentinel 2>&1)"
out="$(printf 'n\n' | dbz "$P3" 'devbox_recreate --docker --fresh-home' 2>&1)"; rc=$?
check "zsh: declining works too" test "$rc" -ne 0
check_eq "zsh: declining keeps the container" "$id_before" "$(cid "$P3_N")"
out="$(dbx "$P3" 'devbox_recreate --bogus' 2>&1)"; rc=$?
check_has "unknown flag prints usage" "usage: devbox_recreate [--docker|--no-docker] [--fresh-home [--yes|-y]] [TAG]" "$out"
check_eq "unknown flag keeps the container" "$id_before" "$(cid "$P3_N")"

out="$(printf 'y\n' | dbz "$P3" 'devbox_recreate --fresh-home' 2>&1)"; rc=$?
check_eq "zsh: answering y resets" 0 "$rc"
check "home reset: sentinel gone" bash -c '! docker exec "$1" test -e /home/dev/sentinel' _ "$P3_N"
in_box "$P3_N" sh -c 'echo keep-me > /home/dev/sentinel'
out="$(dbx "$P3" 'devbox_recreate --fresh-home --yes --docker latest' </dev/null 2>&1)"; rc=$?
check_eq "--fresh-home --yes (flags in any order, with TAG) needs no answer" 0 "$rc"
check "--yes reset: sentinel gone" bash -c '! docker exec "$1" test -e /home/dev/sentinel' _ "$P3_N"
check_eq "other flags still apply (--docker)" 1 "$(label_docker "$P3_N")"
check "reset home re-filled from the image (claude runs)" in_box "$P3_N" claude --version
check "legacy login not copied back" bash -c '! docker exec "$1" test -e /home/dev/.claude/.credentials.json' _ "$P3_N"
check "legacy volumes still kept" bash -c 'docker volume inspect "$1-claude" "$1-history" >/dev/null 2>&1' _ "$P3_N"
check "no 'not carried over' warning on a reset" bash -c '[[ "$1" != *"not carried over"* ]]' _ "$out"
check_has "a reset says the old -claude volume is not copied in" "Not copying the old '${P3_N}-claude'" "$out"
check_has "header says --fresh-home skips the legacy copy" "not copied in again" "$(sed -n '1,/^DEVBOX_DIR=/p' "$ROOT/devbox.zsh")"
docker run -d --name "${P3_N}-holder" -v "${P3_N}-home:/h" "$IMG" sleep infinity >/dev/null
id_before="$(cid "$P3_N")"
out="$(dbx "$P3" 'devbox_recreate --fresh-home --yes' 2>&1)"; rc=$?
check "home used by another container: --fresh-home refuses" test "$rc" -ne 0
check_has "it names the other user" "also used by: ${P3_N}-holder" "$out"
check_eq "refusal keeps the devbox" "$id_before" "$(cid "$P3_N")"
check "refusal keeps the home" vol_exists "${P3_N}-home"
docker rm -f "${P3_N}-holder" >/dev/null

# ---------------------------------------------------------------- AC5
section "devbox_rm keeps the home, --purge deletes it (AC5)"
out="$(dbx "$P3" devbox_rm 2>&1)"; rc=$?
check_eq "devbox_rm" 0 "$rc"
check_has "says it kept the home volume" "Kept this project's home volume '${P3_N}-home'" "$out"
check "container removed" bash -c '! docker inspect "$1" >/dev/null 2>&1' _ "$P3_N"
check "home volume kept" vol_exists "${P3_N}-home"
out="$(dbx "$P3" 'devbox_rm --purge' 2>&1)"
for v in home claude history; do
    check_has "--purge reports deleting -$v" "Deleted volume '${P3_N}-${v}'" "$out"
    check "--purge deleted -$v" bash -c '! docker volume inspect "$1" >/dev/null 2>&1' _ "${P3_N}-${v}"
done
# P4 has no -claude volume: purge must still delete the rest (zsh this time).
out="$(dbz "$P4" 'devbox_rm --purge' 2>&1)"; rc=$?
check_eq "zsh: devbox_rm --purge with a legacy volume missing" 0 "$rc"
check "zsh: --purge deleted -home" bash -c '! docker volume inspect "$1-home" >/dev/null 2>&1' _ "$P4_N"
check "zsh: --purge deleted -history" bash -c '! docker volume inspect "$1-history" >/dev/null 2>&1' _ "$P4_N"
out="$(dbz "$P1" 'devbox_rm' 2>&1)"
check_has "zsh: devbox_rm keeps the home" "Kept this project's home volume" "$out"
check "zsh: home volume kept" vol_exists "${P1_N}-home"

# ---------------------------------------------------------------- AC8
section "header documents the home volume (AC8)"
header="$(sed -n '1,/^DEVBOX_DIR=/p' "$ROOT/devbox.zsh")"
check_has "header names <name>-home"            "<name>-home"  "$header"
check_has "header documents --fresh-home"       "--fresh-home" "$header"
check_has "header documents --yes"              "--yes"        "$header"
check_has "header documents --purge on the home" "--purge: also deletes <name>-home" "$header"
check_has "header says devbox_save misses the home" "devbox_save (docker commit) does not capture the home volume" "$header"
check_has "header says it is sourced from bash too" "~/.bashrc" "$header"
check_has "header says how to redo an interrupted first copy" "docker volume rm <name>-home" "$header"

section "devbox_rm edge cases (AC5)"
# P8 has only a legacy -claude volume (its first copy failed above).
out="$(dbx "$P8" devbox_rm 2>&1)"
check_has "legacy-only project: devbox_rm says the Claude login is kept" "Kept this project's Claude login" "$out"
check "legacy-only project: -claude kept" vol_exists "${P8_N}-claude"
docker run -d --name "${P8_N}-holder" -v "${P8_N}-claude:/c" "$IMG" sleep infinity >/dev/null
out="$(dbx "$P8" 'devbox_rm --purge' 2>&1)"; rc=$?
check_has "--purge reports a volume it could not delete" "Could not delete volume '${P8_N}-claude'" "$out"
check "…and leaves it" vol_exists "${P8_N}-claude"
docker rm -f "${P8_N}-holder" >/dev/null

section "--fresh-home without a home volume (AC4)"
new_project P9
out="$(dbx "$P9" 'devbox_recreate --fresh-home' </dev/null 2>&1)"; rc=$?
check_eq "nothing to delete: creates without asking" 0 "$rc"
check "…no question asked" bash -c '[[ "$1" != *"[y/N]"* ]]' _ "$out"
check "…and the home volume exists" vol_exists "${P9_N}-home"
out="$(dbx "$P9" 'devbox_recreate --fresh-home -y' </dev/null 2>&1)"; rc=$?
check_eq "-y confirms like --yes" 0 "$rc"
check_has "-y: home deleted and recreated" "Deleted '${P9_N}-home'" "$out"
out="$(dbz "$P9" 'devbox_recreate --docker' 2>&1)"; rc=$?
check_eq "zsh: devbox_recreate --docker (docker args array)" 0 "$rc"
check_eq "zsh: --docker label set" 1 "$(label_docker "$P9_N")"
