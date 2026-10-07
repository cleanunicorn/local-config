# shell-helpers

Small zsh helper functions I use every day.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/cleanunicorn/shell-helpers/main/install.sh | sh
```

This clones the repo into `~/.local/share/shell-helpers` (override with
`SHELL_HELPERS_DIR`) and adds one `source` line to your `~/.zshrc`.
Already have a checkout? Run `./install.sh` from inside it instead.
Running it again is safe; it won't add the line twice.

Update later with `git pull` in the checkout.

The functions are **sourced**, not run as scripts, because some of them
(`ghclone`, the attach commands) need to act on your current shell.
The entry point `shell-helpers.zsh` loads every file in `zsh/`.

## Modules

### `zsh/ghclone.zsh`

`ghclone <github-url>` clones into `$GHCLONE_ROOT/<user>/<repo>` and `cd`s
into it. If the directory already exists, it just `cd`s there. Takes https
and ssh URLs. `GHCLONE_ROOT` defaults to `~/Development/github.com`.

### `zsh/zellij.zsh`

Needs `zellij` and `fzf`. Run `zlh` for help.

| Command | What it does |
| --- | --- |
| `zl [name]` | Attach to the session named after the current folder (or `name`); asks first if it exists, creates it otherwise |
| `zla` | Fuzzy-pick a session and attach |
| `zlk` | Fuzzy-pick a session and kill it (state kept, resurrectable) |
| `zld` | Delete all exited sessions (permanent) |
| `zldx <name>` | Delete one exited session (permanent) |

### `zsh/herdr.zsh`

Needs `herdr`, `jq` and `fzf`. Run `hrh` for help.

| Command | What it does |
| --- | --- |
| `hr [name]` | Attach to the session named after the current folder (or `name`); asks first if it exists, creates it otherwise |
| `hra` | Fuzzy-pick a session and attach (falls back to `hr` if there are none) |
| `hrk` | Fuzzy-pick a running session and stop it (state kept) |
| `hrd` | Delete all stopped sessions (permanent) |
| `hrdx <name>` | Delete one stopped session (permanent) |

## Adding a module

Drop a new `.zsh` file into `zsh/`. It's picked up on the next shell start.

## License

MIT
