# devbox

One long-lived Docker container per project folder, with Claude Code, Node 22,
`gh`, and herdr preinstalled. Shell functions for zsh and bash.

## Install

```sh
git clone git@github.com:cleanunicorn/devbox.git ~/.devbox
echo '[ -f "$HOME/.devbox/devbox.zsh" ] && source "$HOME/.devbox/devbox.zsh"' >> ~/.zshrc   # or ~/.bashrc
source ~/.devbox/devbox.zsh
devbox_build
```

Then, in any project folder: `devbox_shell`.

## Update

```sh
devbox_update        # git pull + reload the functions in this shell
```

If the image changed, `devbox_update` says so: run `devbox_build`, then
`devbox_recreate` in each project. (A plain `git -C ~/.devbox pull` also works;
new shells pick up the scripts automatically.)

## Commands

The full list, with options, is at the top of [`devbox.zsh`](devbox.zsh). The main ones:

| Command | What it does |
|---|---|
| `devbox_shell [--docker]` | create/start this folder's devbox and open a shell |
| `devbox_recreate [--docker\|--no-docker] [--fresh-home [--yes]]` | move the devbox onto a new image, keeping its home volume |
| `devbox_port [--lan] CPORT [HPORT]` | forward a container port to the host |
| `devbox_rm [--purge]` | remove the devbox (`--purge` also deletes its home volume) |
| `devbox_tmp [--docker]` | throwaway devbox, removed on exit |

- **Home volume:** each project's `/home/dev` lives on `<name>-home`, so logins (Claude, `gh`), git config and caches survive recreates.
- **`--docker`:** gives the devbox the host's Docker daemon (root-equivalent on the host; off by default). `docker compose` stacks started inside are reachable by service name and on `127.0.0.1` like on the host.

## Tests

```sh
bash tests/run.sh              # syntax + Docker integration test (isolated image/network)
bash tests/run.sh --syntax-only
```

Linux only (uses `stat -c`, `ss`, uid 1000).
