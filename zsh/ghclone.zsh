# ─── ghclone ─────────────────────────────────────────────────────

# Clone a GitHub repo into $GHCLONE_ROOT/<user>/<repo> and cd into it.
# Accepts https and ssh URLs. If the directory already exists, just cd.
# GHCLONE_ROOT defaults to ~/Development/github.com.
ghclone() {
  if [[ -z "$1" ]]; then
    echo "Usage: ghclone <github-url>"
    return 1
  fi

  local url="$1"
  local user repo

  # Extract "user" and "repo" from both https and ssh formats
  if [[ "$url" =~ github\.com[:/]+([^/]+)/([^/]+)(\.git)?$ ]]; then
    user="${match[1]}"
    repo="${match[2]}"
    repo="${repo%.git}"
  else
    echo "Error: Could not parse GitHub URL: $url"
    return 1
  fi

  local base_dir="${GHCLONE_ROOT:-$HOME/Development/github.com}/$user"
  local target_dir="$base_dir/$repo"

  mkdir -p "$base_dir"

  if [[ -d "$target_dir" ]]; then
    echo "Directory already exists: $target_dir"
  else
    git clone "$url" "$target_dir"
  fi

  cd "$target_dir" || return 1
}
