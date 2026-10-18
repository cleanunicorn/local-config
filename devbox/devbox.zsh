# Devbox — one long-lived container per project folder, built from
# ~/.devbox/Dockerfile. Sourced from ~/.zshrc and ~/.bashrc (works in both).
#
#   devbox_shell [--docker]     create/start this folder's devbox and open a shell
#   devbox_stop                 stop this folder's devbox (keeps it, 'devbox_shell' restarts)
#   devbox_port [--lan] CPORT [HPORT]
#                               forward container port CPORT to 127.0.0.1:HPORT
#                               (--lan: 0.0.0.0:HPORT, reachable from your network)
#   devbox_ports                list this folder's forwards
#   devbox_unport HPORT         remove a forward
#   devbox_build [TAG]          rebuild the image (tags :latest and :TAG/date);
#                               re-downloads herdr each time (HERDR_VERSION=latest)
#   devbox_update               git pull this repo and reload these functions
#                               (says when the image needs a devbox_build)
#   devbox_recreate [--docker|--no-docker] [--fresh-home [--yes|-y]] [TAG]
#                               move this folder's devbox onto a new image, keeping
#                               its home volume (--fresh-home: delete the home and
#                               start again from the image; asks y/N first, --yes or -y
#                               skips the question)
#   devbox_save [TAG]           snapshot this folder's container as devbox:TAG
#   devbox_rm [--purge]         remove this folder's devbox; keeps its home volume
#                               (--purge: also deletes <name>-home and the old
#                               <name>-claude / <name>-history volumes)
#   devbox_tmp [--docker]       throwaway devbox, removed on exit (no home volume)
#
# --docker mounts the host's Docker socket so the devbox can run docker /
# docker compose against the host daemon (see, build and run its images and
# containers). Off by default: socket access is root-equivalent on the host.
# The choice is stored on the container and kept across devbox_recreate.
# Bind mounts you pass to docker inside resolve on the HOST, so use
# $DEVBOX_HOST_WORKSPACE (the project's host path), not /workspace.
# Compose inside uses the folder's name as project name (as on the host, so
# existing volumes are reused), and the devbox auto-joins that stack: service
# names resolve and published ports answer on the devbox's 127.0.0.1 too
# (bin/devbox-compose-link, run after each `docker compose` and on devbox_shell).
#
# Home volume: each project's whole /home/dev lives on its own named volume,
# <name>-home, so GitHub (gh) login, ~/.gitconfig, Claude login, shell history,
# caches and tool configs survive devbox_recreate. A new home is filled from
# the image's /home/dev; if the project still has the old <name>-claude /
# <name>-history volumes, their contents are copied in once (the old volumes
# are left alone until devbox_rm --purge; if that first copy is cut short,
# e.g. the terminal closes, run `docker volume rm <name>-home` and
# devbox_recreate to copy again). Files that lived only inside an
# older container's /home/dev are not carried over. Image changes inside
# /home/dev (skeleton dotfiles, the Claude binary — Claude updates itself) do
# not reach an existing home; --fresh-home resets it, starting from the image
# only (the old -claude/-history volumes are not copied in again). Shell
# settings the image provides live in /etc/bash.bashrc, outside the home, so
# they always apply.
#
# What survives a recreate: the project folder (bind mount), the home volume
# and port forwards (separate sidecar containers). Installs outside /home/dev
# (apt packages) do not — put them in the Dockerfile, or devbox_save first.
# devbox_save (docker commit) does not capture the home volume: a saved image
# has the container's system changes, not what is in /home/dev.
#
# The old names (dev_container, del_container, new_container) still work as
# aliases.

DEVBOX_DIR="${DEVBOX_DIR:-$HOME/.devbox}"
DEVBOX_IMAGE="${DEVBOX_IMAGE:-devbox}"
DEVBOX_NET="${DEVBOX_NET:-devnet}"

# Consistent container name from the current folder path — unchanged from the
# original helper so existing names stay stable.
_get_container_name() {
    local sanitized_path=$(echo "$PWD" | tr '/' '_' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]//g' | tr -s '_')
    sanitized_path=$(echo "$sanitized_path" | sed 's/^[^a-z0-9]*//')
    if [[ -z "$sanitized_path" ]] || [[ ! "$sanitized_path" =~ ^[a-z0-9] ]]; then
        sanitized_path="dev_${sanitized_path}"
    fi
    echo "dev${sanitized_path}"
}

_devbox_exists() {
    docker ps -a --filter "name=^${1}$" --format '{{.Names}}' | grep -qx "$1"
}

_devbox_running() {
    [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]
}

# A user-defined bridge gives containers DNS names, which is how a port
# sidecar finds its devbox — and keeps finding it after a recreate.
_devbox_ensure_net() {
    docker network inspect "$DEVBOX_NET" >/dev/null 2>&1 || docker network create "$DEVBOX_NET" >/dev/null
}

DEVBOX_DOCKER_SOCK="${DEVBOX_DOCKER_SOCK:-/var/run/docker.sock}"

# Sets _DEVBOX_DOCKER_ARGS to the docker run flags that hand the host's Docker
# daemon to a devbox. The socket is owned by the host's docker group, so the
# container user joins that gid. (An array, not echo, so it works in bash too.)
# COMPOSE_PROJECT_NAME: compose would name the project after /workspace;
# use the host folder's name, normalised the way compose does it.
_devbox_docker_args() {
    local name="$1"
    [[ -S "$DEVBOX_DOCKER_SOCK" ]] || { echo "No Docker socket at ${DEVBOX_DOCKER_SOCK}." >&2; return 1; }
    local project="$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g; s/^[^a-z0-9]*//')"
    _DEVBOX_DOCKER_ARGS=(
        -v "${DEVBOX_DOCKER_SOCK}:/var/run/docker.sock"
        --group-add "$(stat -c %g "$DEVBOX_DOCKER_SOCK")"
        -e "DEVBOX_HOST_WORKSPACE=$PWD"
        -e "DEVBOX_NAME=$name"
        -e "COMPOSE_PROJECT_NAME=${project:-workspace}"
        --label devbox.docker=1
    )
}

_devbox_has_docker() {
    [[ "$(docker inspect -f '{{index .Config.Labels "devbox.docker"}}' "$1" 2>/dev/null)" == "1" ]]
}

# Per-project volumes from before the home volume existed, NAME-<suffix>,
# once mounted at /home/dev/.<suffix>. Read once for migration; --purge deletes them.
_DEVBOX_LEGACY=(claude history)

_devbox_volume_exists() {
    docker volume inspect "$1" >/dev/null 2>&1
}

# _devbox_home_volume NAME IMAGE [MIGRATE(0|1)]
# Makes sure this project's home volume NAME-home exists. Docker fills a new,
# empty one from the image's /home/dev the first time it is mounted. With
# MIGRATE (the default), a new one also gets the contents of the pre-home
# volumes NAME-claude / NAME-history, if they exist; those are only read and
# are left in place. Sets _DEVBOX_HOME_NEW=1 when it created the volume.
_devbox_home_volume() {
    local name="$1" image="$2" migrate="${3:-1}" home="${1}-home"
    _DEVBOX_HOME_NEW=0
    _devbox_volume_exists "$home" && return 0
    docker volume create "$home" >/dev/null || { echo "Could not create volume '${home}'." >&2; return 1; }
    _DEVBOX_HOME_NEW=1
    (( migrate )) || return 0
    # Mount only the legacy volumes that exist: -v would create a missing one.
    local -a mounts=() found=()
    local d
    for d in "${_DEVBOX_LEGACY[@]}"; do
        if _devbox_volume_exists "${name}-${d}"; then
            mounts+=(-v "${name}-${d}:/legacy/${d}:ro")
            found+=("$d")
        fi
    done
    (( ${#found[@]} )) || return 0
    # The first mount fills the volume from the image; then the old data goes on top.
    if docker run --rm --network none --user 0 -v "${home}:/home/dev" "${mounts[@]}" "$image" sh -c '
        for d in "$@"; do
            mkdir -p "/home/dev/.$d" && cp -a "/legacy/$d/." "/home/dev/.$d/" && chown -R 1000:1000 "/home/dev/.$d" || exit 1
        done' sh "${found[@]}" >/dev/null; then
        echo "Copied this project's Claude login and history into '${home}' (old volumes left in place)."
    else
        docker volume rm "$home" >/dev/null 2>&1
        echo "Could not copy the old Claude login/history into '${home}' — nothing was changed." >&2
        return 1
    fi
}

# _devbox_create NAME [IMAGE] [DOCKER(0|1)] [MIGRATE(0|1)]
_devbox_create() {
    local name="$1" image="${2:-${DEVBOX_IMAGE}:latest}" with_docker="${3:-0}" migrate="${4:-1}"
    local -a extra=()
    if (( with_docker )); then
        _devbox_docker_args "$name" || return 1
        extra=("${_DEVBOX_DOCKER_ARGS[@]}")
    fi
    _devbox_ensure_net
    _devbox_home_volume "$name" "$image" "$migrate" || return 1
    docker run -d \
        --name "$name" \
        --hostname devbox \
        --restart unless-stopped \
        --network "$DEVBOX_NET" \
        --network-alias "$(_devbox_alias "$name")" \
        --label devbox.role=main \
        --label "devbox.project=$name" \
        -v "$PWD":/workspace \
        -v "${name}-home":/home/dev \
        -w /workspace \
        "${extra[@]}" \
        "$image" >/dev/null
}

# Container names come from the folder path, so they can exceed DNS's 63-char
# label limit or contain dots (github.com) — neither resolves on the bridge.
# Sidecars target this short, stable alias instead.
_devbox_alias() {
    echo "devbox-$(printf '%s' "$1" | sha1sum | cut -c1-12)"
}

_devbox_port_sidecars() {
    docker ps -a --filter label=devbox.role=port --filter "label=devbox.project=$1" --format '{{.Names}}'
}

devbox_shell() {
    local name="$(_get_container_name)" with_docker=0
    case "$1" in
        --docker) with_docker=1 ;;
        "") ;;
        *) echo "usage: devbox_shell [--docker]"; return 1 ;;
    esac
    if _devbox_exists "$name"; then
        local image="$(docker inspect -f '{{.Config.Image}}' "$name")"
        if [[ "$image" != ${DEVBOX_IMAGE}:* ]]; then
            echo "Container '${name}' is not a devbox (image: ${image})."
            echo "Run 'devbox_rm' then 'devbox_shell' to replace it."
            return 1
        fi
        if (( with_docker )) && ! _devbox_has_docker "$name"; then
            echo "'${name}' was created without Docker access — 'devbox_recreate --docker' to add it."
            return 1
        fi
        if [[ "$(docker inspect -f '{{.Image}}' "$name")" != "$(docker image inspect -f '{{.Id}}' "${DEVBOX_IMAGE}:latest" 2>/dev/null)" ]]; then
            echo "Note: '${name}' runs an older image than ${DEVBOX_IMAGE}:latest — 'devbox_recreate' to update."
        fi
        _devbox_running "$name" || { echo "Starting '${name}'..."; docker start "$name" >/dev/null; }
    else
        echo "Creating devbox '${name}'$( (( with_docker )) && echo ' with Docker access')..."
        _devbox_create "$name" "" "$with_docker" || return 1
    fi
    # Re-link to a compose stack that's already up (e.g. after a recreate).
    _devbox_has_docker "$name" && docker exec -d "$name" devbox-compose-link
    # SHELL: docker doesn't set it, so tools that spawn a shell (herdr, tmux)
    # would fall back to /bin/sh — no history, arrow keys print ^[[A.
    docker exec -it -e TERM="${TERM:-xterm-256color}" -e COLORTERM="${COLORTERM:-}" -e SHELL=/bin/bash "$name" bash
}

devbox_stop() {
    local name="$(_get_container_name)"
    _devbox_exists "$name" || { echo "No devbox for this folder — run devbox_shell first."; return 1; }
    if _devbox_running "$name"; then
        docker stop "$name" >/dev/null && echo "Stopped '${name}' ('devbox_shell' to start it again)."
    else
        echo "'${name}' is not running."
    fi
}

devbox_port() {
    local bind=127.0.0.1
    [[ "$1" == "--lan" ]] && { bind=0.0.0.0; shift; }
    local cport="$1" hport="${2:-$1}"
    local name="$(_get_container_name)"
    if [[ ! "$cport" =~ ^[0-9]+$ || ! "$hport" =~ ^[0-9]+$ ]]; then
        echo "usage: devbox_port [--lan] CONTAINER_PORT [HOST_PORT]"; return 1
    fi
    _devbox_exists "$name" || { echo "No devbox for this folder — run devbox_shell first."; return 1; }
    local sidecar="${name}-p${hport}"
    if _devbox_exists "$sidecar"; then
        echo "Host port ${hport} is already forwarded for this project ('devbox_unport ${hport}' first)."; return 1
    fi
    if ss -ltnH "sport = :${hport}" 2>/dev/null | grep -q .; then
        echo "Host port ${hport} is already in use:"
        ss -ltnpH "sport = :${hport}" 2>/dev/null
        docker ps --filter "publish=${hport}" --format '  container: {{.Names}}'
        return 1
    fi
    _devbox_ensure_net
    docker run -d \
        --name "$sidecar" \
        --restart unless-stopped \
        --network "$DEVBOX_NET" \
        --label devbox.role=port \
        --label "devbox.project=$name" \
        --label "devbox.cport=$cport" \
        --label "devbox.hport=$hport" \
        --label "devbox.bind=$bind" \
        -p "${bind}:${hport}:${hport}" \
        alpine/socat "TCP-LISTEN:${hport},fork,reuseaddr" "TCP:$(_devbox_alias "$name"):${cport}" >/dev/null || return 1
    echo "http://localhost:${hport}  →  devbox:${cport}"
    if [[ "$bind" == 0.0.0.0 ]]; then
        local ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
        echo "http://${ip:-<this-machine>}:${hport}  (from your network)"
    fi
    echo "(the server inside must listen on 0.0.0.0, not localhost — e.g. vite --host)"
}

devbox_ports() {
    local name="$(_get_container_name)"
    local rows="$(docker ps -a --filter label=devbox.role=port --filter "label=devbox.project=$name" \
        --format '{{if eq (.Label "devbox.bind") "0.0.0.0"}}0.0.0.0{{else}}localhost{{end}}:{{.Label "devbox.hport"}}\t→ devbox:{{.Label "devbox.cport"}}\t{{.Status}}')"
    [[ -n "$rows" ]] && printf '%s\n' "$rows" || echo "No port forwards for this project."
}

devbox_unport() {
    local hport="$1" name="$(_get_container_name)"
    [[ -n "$hport" ]] || { echo "usage: devbox_unport HOST_PORT"; return 1; }
    if _devbox_exists "${name}-p${hport}"; then
        docker rm -f "${name}-p${hport}" >/dev/null && echo "Removed forward on host port ${hport}."
    else
        echo "No forward on host port ${hport} for this project."; return 1
    fi
}

devbox_build() {
    local tag="${1:-$(date +%F)}"
    local -a args=(--build-arg "HERDR_CACHE_BUST=$(date +%s)")
    [[ -S "$DEVBOX_DOCKER_SOCK" ]] && args+=(--build-arg "DOCKER_GID=$(stat -c %g "$DEVBOX_DOCKER_SOCK")")
    docker build "${args[@]}" -t "${DEVBOX_IMAGE}:latest" -t "${DEVBOX_IMAGE}:${tag}" "$DEVBOX_DIR" \
        && echo "Built ${DEVBOX_IMAGE}:latest and ${DEVBOX_IMAGE}:${tag}. Run 'devbox_recreate' in a project to move it over."
}

# Pulls the devbox repo and reloads these functions into the current shell.
# Image inputs (Dockerfile, bin/) only take effect after devbox_build.
devbox_update() {
    local before after
    before="$(git -C "$DEVBOX_DIR" rev-parse HEAD)" || return 1
    git -C "$DEVBOX_DIR" pull --ff-only || return 1
    after="$(git -C "$DEVBOX_DIR" rev-parse HEAD)"
    [[ "$before" == "$after" ]] && return 0   # git already said "Already up to date."
    source "$DEVBOX_DIR/devbox.zsh"
    echo "Updated and reloaded devbox.zsh (other open shells: 'source ~/.devbox/devbox.zsh' or open a new one)."
    if [[ -n "$(git -C "$DEVBOX_DIR" diff --name-only "$before" "$after" -- Dockerfile bin)" ]]; then
        echo "The image changed — run 'devbox_build', then 'devbox_recreate' in each project."
    fi
}

devbox_recreate() {
    local name="$(_get_container_name)" with_docker="" fresh=0 yes=0
    local home="${name}-home"
    while (( $# )); do
        case "$1" in
            --docker) with_docker=1 ;;
            --no-docker) with_docker=0 ;;
            --fresh-home) fresh=1 ;;
            --yes|-y) yes=1 ;;
            -*) echo "usage: devbox_recreate [--docker|--no-docker] [--fresh-home [--yes|-y]] [TAG]"; return 1 ;;
            *) break ;;
        esac
        shift
    done
    local image="${DEVBOX_IMAGE}:${1:-latest}"
    docker image inspect "$image" >/dev/null 2>&1 || { echo "No image ${image}."; return 1; }
    # No flag: keep whatever Docker access the existing devbox had.
    if [[ -z "$with_docker" ]]; then
        _devbox_has_docker "$name" && with_docker=1 || with_docker=0
    fi
    # --fresh-home: ask before anything is removed; the home holds logins.
    if (( fresh && ! yes )) && _devbox_volume_exists "${home}"; then
        local reply=""
        printf "Delete '%s' (GitHub/Claude logins, git config, history, caches, tools installed in your home) and start again from the image? [y/N] " "$home"
        read -r reply
        case "$reply" in
            y|Y|yes|YES|Yes) ;;
            *)
                echo "Cancelled — nothing changed."
                [[ -t 0 ]] || echo "(No terminal to answer from: add --yes to confirm.)"
                return 1 ;;
        esac
    fi
    local note="" kept="home volume and port forwards are kept"
    (( with_docker )) && note=", with Docker access"
    (( fresh )) && kept="fresh home volume; port forwards are kept"
    # Everything that can fail runs while the old container still stands.
    local existed=0 home_new=0 users=""
    _devbox_exists "$name" && existed=1
    if (( fresh )); then
        # The home can only be deleted once nothing mounts it.
        users="$(docker ps -a --filter "volume=${home}" --format '{{.Names}}' | grep -vx "$name" | tr '\n' ' ')"
        if [[ -n "$users" ]]; then
            echo "'${home}' is also used by: ${users}— remove those containers first. Nothing changed." >&2
            return 1
        fi
    else
        # Creates the home (copying any old -claude/-history in) before the
        # container goes; on failure the old devbox is untouched.
        _devbox_home_volume "$name" "$image" 1 || return 1
        home_new="$_DEVBOX_HOME_NEW"
    fi
    if (( existed )); then
        echo "Recreating '${name}' on ${image}${note} (${kept})..."
        if (( home_new )); then
            echo "New home volume '${home}': files that lived only in the old container's /home/dev (e.g. gh login, ~/.gitconfig) are not carried over."
        fi
        docker rm -f "$name" >/dev/null
    else
        echo "Creating devbox '${name}' on ${image}${note}..."
    fi
    if (( fresh )) && _devbox_volume_exists "${home}"; then
        if ! docker volume rm "${home}" >/dev/null; then
            echo "Could not delete '${home}'; the devbox container is already removed. Free the volume (docker ps -a --filter volume=${home}), then run 'devbox_recreate --fresh-home' again." >&2
            return 1
        fi
        echo "Deleted '${home}'."
    fi
    # A fresh home starts from the image only: the old -claude/-history are not copied back.
    local migrate=1 d
    if (( fresh )); then
        migrate=0
        for d in "${_DEVBOX_LEGACY[@]}"; do
            _devbox_volume_exists "${name}-${d}" && echo "Not copying the old '${name}-${d}' into the fresh home (kept; 'devbox_rm --purge' deletes it)."
        done
    fi
    _devbox_create "$name" "$image" "$with_docker" "$migrate" || return 1
    # Sidecars reconnect by name on each connection; restarting them just
    # clears any that gave up while the devbox was gone.
    local s
    for s in $(_devbox_port_sidecars "$name"); do docker restart "$s" >/dev/null; done
    echo "Done. 'devbox_shell' to open a shell."
}

devbox_save() {
    local tag="${1:-snapshot-$(date +%F-%H%M)}" name="$(_get_container_name)"
    _devbox_exists "$name" || { echo "No devbox for this folder."; return 1; }
    docker commit "$name" "${DEVBOX_IMAGE}:${tag}" >/dev/null \
        && echo "Saved as ${DEVBOX_IMAGE}:${tag} — 'devbox_recreate ${tag}' to use it. Move the change into the Dockerfile when you can."
}

devbox_rm() {
    local name="$(_get_container_name)" purge=0
    local home="${name}-home"
    [[ "$1" == "--purge" ]] && purge=1
    local s
    for s in $(_devbox_port_sidecars "$name"); do docker rm -f "$s" >/dev/null && echo "Removed forward '${s}'."; done
    if _devbox_exists "$name"; then
        docker rm -f "$name" >/dev/null && echo "Container '${name}' deleted."
    else
        echo "No container found for the current folder with name '${name}'."
    fi
    local v
    if (( purge )); then
        # One at a time, so a missing legacy volume doesn't stop the others.
        for v in home "${_DEVBOX_LEGACY[@]}"; do
            v="${name}-${v}"
            _devbox_volume_exists "$v" || continue
            if docker volume rm "$v" >/dev/null; then
                echo "Deleted volume '${v}'."
            else
                echo "Could not delete volume '${v}'."
            fi
        done
    elif _devbox_volume_exists "${home}"; then
        echo "Kept this project's home volume '${home}' (logins, git config, history) — 'devbox_rm --purge' to delete it."
    elif _devbox_volume_exists "${name}-claude"; then
        echo "Kept this project's Claude login (devbox_rm --purge to remove it)."
    fi
    return 0
}

devbox_tmp() {
    # Named so a --docker throwaway can join compose networks by name.
    local name="$(_get_container_name)-tmp-$$"
    local -a extra=()
    case "$1" in
        --docker) _devbox_docker_args "$name" || return 1; extra=("${_DEVBOX_DOCKER_ARGS[@]}") ;;
        "") ;;
        *) echo "usage: devbox_tmp [--docker]"; return 1 ;;
    esac
    docker run -it --rm --name "$name" -e TERM="${TERM:-xterm-256color}" -e COLORTERM="${COLORTERM:-}" -v "$PWD":/workspace -w /workspace "${extra[@]}" "${DEVBOX_IMAGE}:latest" bash
}

# Old names, kept so muscle memory still works.
dev_container() { devbox_shell "$@"; }
del_container() { devbox_rm "$@"; }
new_container() { devbox_tmp "$@"; }
