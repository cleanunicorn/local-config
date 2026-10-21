# devbox

One long-lived Docker container per project folder, with Claude Code, Node 22,
`gh`, and herdr preinstalled. Shell functions for zsh and bash.

## Install

Part of [local-config](../README.md): `./install.sh` there makes `~/.zshrc`
load `local-config.zsh`, which loads these functions (`zsh/devbox.zsh`). Then
build the image once:

```sh
devbox_build
```

and, in any project folder, `devbox_shell`.

For bash, source the file directly from `~/.bashrc`:

```sh
[ -f ~/Development/github.com/cleanunicorn/local-config/devbox/devbox.zsh ] && \
    source ~/Development/github.com/cleanunicorn/local-config/devbox/devbox.zsh
```

## Update

```sh
devbox_update        # git pull local-config + reload the functions in this shell
```

If the image changed, `devbox_update` says so: run `devbox_build`, then
`devbox_recreate` in each project. (A plain `git pull` in local-config also
works; new shells pick up the scripts automatically.)

## Commands

The full list, with options, is at the top of [`devbox.zsh`](devbox.zsh). The main ones:

| Short | Command | What it does |
|---|---|---|
| `dv [--docker]` | `devbox_shell` | create/start this folder's devbox and open a shell |
| `dvr [--docker\|--no-docker] [--fresh-home [--yes]]` | `devbox_recreate` | move the devbox onto a new image, keeping its home volume |
| `dvp [--lan] CPORT [HPORT]` | `devbox_port` | forward a container port to the host |
| `dvd [--purge]` | `devbox_rm` | remove the devbox (`--purge` also deletes its home volume) |
| `dvt [--docker]` | `devbox_tmp` | throwaway devbox, removed on exit |

Every command has a short `dv*` name next to its `devbox_*` one (both work):
`dv` shell, `dvk` stop, `dvp`/`dvpl`/`dvpx` add/list/remove forwards, `dvb`
build, `dvr` recreate, `dvu` update, `dvs` save, `dvd` delete, `dvt`
throwaway. `dvh` prints them all.

- **Home volume:** each project's `/home/dev` lives on `<name>-home`, so logins (Claude, `gh`), git config and caches survive recreates.
- **`--docker`:** gives the devbox the host's Docker daemon (root-equivalent on the host; off by default). `docker compose` stacks started inside are reachable by service name and on `127.0.0.1` like on the host.

## Tests

```sh
bash devbox/tests/run.sh              # syntax + Docker integration test (isolated image/network)
bash devbox/tests/run.sh --syntax-only
```

Linux only (uses `stat -c`, `ss`, uid 1000).
