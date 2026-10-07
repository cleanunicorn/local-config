# local-config

My shell helpers and app config, kept in one git repo and linked into place.

## Install

```sh
git clone https://github.com/cleanunicorn/local-config.git
cd local-config
./install.sh --dry-run   # show what would change
./install.sh
```

`install.sh` does two things, and is safe to run again:

1. **Links config files.** Every file under `home/` is symlinked to the same
   path under `$HOME`, e.g. `home/.config/herdr/config.toml` →
   `~/.config/herdr/config.toml`. The file stays in this repo, so edits show up
   in `git status`. A file already in the way is moved to
   `<name>.bak-<timestamp>`.
2. **Loads the shell helpers.** Adds one line to `~/.zshrc` that sources
   `local-config.zsh`, which loads every file in `zsh/`.

Update later with `git pull`. Links pick up changes straight away; open a new
shell for helper changes.

## Layout

```
home/               mirrors $HOME; each file gets symlinked into place
  .config/herdr/config.toml
zsh/                zsh helpers, sourced by local-config.zsh
local-config.zsh    entry point for ~/.zshrc
install.sh
```

To add a config file, put it under `home/` at the same path it has under
`$HOME` and run `./install.sh`. To add helpers, drop a `.zsh` file into `zsh/`.

No secrets here: this repo is public. Keep tokens and API keys in a file that
isn't tracked (e.g. `~/.secrets.zsh`).

## Config

| File | For |
| --- | --- |
| `home/.config/herdr/config.toml` | Herdr: gruvbox theme, symbol status indicators, alt+cmd+arrows to move between panes |

## Shell helpers

The helpers are **sourced**, not run as scripts, because some of them
(`ghclone`, the attach commands) need to act on your current shell. They're
zsh-only.

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

## License

MIT
