# ─── ghclone ─────────────────────────────────────────────────────

# Clone a GitHub repo into $GHCLONE_ROOT/<user>/<repo> and cd into it.
# If the directory already exists, just cd.
#
# Accepts anything that names a repo:
#   https://github.com/user/repo[.git][/][/tree/main/…][?…][#…]
#   git@github.com:user/repo.git, ssh://git@github.com/user/repo
#   github.com/user/repo, user/repo
#
# The clone URL is rebuilt from user/repo. URLs keep their protocol (ssh or
# https); user/repo shorthand uses $GHCLONE_PROTOCOL (default https).
# GHCLONE_ROOT defaults to ~/Development/github.com.
ghclone() {
  if [[ -z "$1" ]]; then
    echo "Usage: ghclone <github-url | user/repo>"
    return 1
  fi

  local url="${1%%[?#]*}"   # drop ?query and #fragment
  local user repo protocol
  local shorthand_re='^([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)/?$'
  local url_re='(^|[@/.])github\.com[:/]+([^/]+)/([^/]+)'

  if [[ "$url" =~ $shorthand_re ]]; then
    user="${match[1]}"
    repo="${match[2]}"
    protocol="${GHCLONE_PROTOCOL:-https}"
  elif [[ "$url" =~ $url_re ]]; then
    user="${match[2]}"
    repo="${match[3]}"
    if [[ "$url" == git@* || "$url" == ssh://* ]]; then
      protocol=ssh
    else
      protocol=https
    fi
  else
    echo "Error: Could not parse GitHub URL: $1"
    return 1
  fi
  repo="${repo%.git}"

  local clone_url
  if [[ "$protocol" == ssh ]]; then
    clone_url="git@github.com:$user/$repo.git"
  else
    clone_url="https://github.com/$user/$repo.git"
  fi

  local base_dir="${GHCLONE_ROOT:-$HOME/Development/github.com}/$user"
  local target_dir="$base_dir/$repo"

  mkdir -p "$base_dir"

  if [[ -d "$target_dir" ]]; then
    echo "Directory already exists: $target_dir"
  else
    git clone "$clone_url" "$target_dir"
  fi

  cd "$target_dir" || return 1
}
