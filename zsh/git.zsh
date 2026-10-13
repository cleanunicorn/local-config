# ─── Git helpers ──────────────────────────────────────────────

# Print the repo's default branch: origin/HEAD, else a local main or master.
_git_default_branch() {
    local ref b
    if ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; then
        print -r -- "${ref#origin/}"
        return
    fi
    for b in main master; do
        git show-ref --verify --quiet "refs/heads/$b" && { print -r -- "$b"; return; }
    done
    return 1
}

# Switch to the default branch (main or master) and pull.
gup() {
    git rev-parse --git-dir >/dev/null || return
    local default
    default="$(_git_default_branch)" || { echo "Can't tell the default branch."; return 1; }
    git switch "$default" && git pull --prune
}

# After a PR is merged: switch to the default branch, pull, and delete the
# branch you were on. Keeps the branch if it isn't merged.
gdone() {
    git rev-parse --git-dir >/dev/null || return
    local branch default local_sha pr_json
    branch="$(git branch --show-current)"
    default="$(_git_default_branch)" || { echo "Can't tell the default branch."; return 1; }
    [[ -n "$branch" && "$branch" != "$default" ]] || {
        echo "Run gdone from the branch you're done with."; return 1; }

    gup || return
    if git merge-base --is-ancestor "$branch" HEAD; then
        git branch -D "$branch"
        return
    fi

    # Squash and rebase merges leave the branch looking unmerged; ask GitHub.
    # Only delete it if the merged PR has exactly what's on the local branch.
    local_sha="$(git rev-parse "$branch")"
    pr_json="$(gh pr view "$branch" --json state,headRefOid 2>/dev/null)"
    if [[ "$(print -r -- "$pr_json" | jq -r .state)" == MERGED &&
          "$(print -r -- "$pr_json" | jq -r .headRefOid)" == "$local_sha" ]]; then
        git branch -D "$branch"
    else
        echo "Kept $branch: it isn't merged into $default (or has commits the PR doesn't)."
        return 1
    fi
}
