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

Short commands for the things I do many times a day: cloning a repo into a
predictable place, and getting back into the right terminal session for the
folder I'm in.

The helpers are **sourced**, not run as scripts, because some of them
(`ghclone`, the attach commands) need to act on your current shell. They're
zsh-only.

| Command | Module | One-liner |
| --- | --- | --- |
| [`ghclone <url>`](#ghclone) | ghclone | Clone into `~/Development/github.com/<user>/<repo>` and `cd` there |
| [`zl [name]`](#zl-name) | Zellij | Open the Zellij session for this folder |
| [`zla`](#zla) | Zellij | Pick a Zellij session from a list and attach |
| [`zlk`](#zlk) | Zellij | Pick a Zellij session and kill it (can be resurrected) |
| [`zld`](#zld) | Zellij | Delete every exited Zellij session |
| [`zldx <name>`](#zldx-name) | Zellij | Delete one exited Zellij session |
| [`zlh`](#zellij) | Zellij | Print the Zellij help |
| [`hr [name]`](#hr-name) | Herdr | Open the Herdr session for this folder |
| [`hra`](#hra) | Herdr | Pick a Herdr session from a list and attach |
| [`hrk`](#hrk) | Herdr | Pick a running Herdr session and stop it |
| [`hrd`](#hrd) | Herdr | Delete every stopped Herdr session |
| [`hrdx <name>`](#hrdx-name) | Herdr | Delete one stopped Herdr session |
| [`hrh`](#herdr) | Herdr | Print the Herdr help |

### ghclone

*`zsh/ghclone.zsh`. Needs `git`.*

Every repo lands at `<root>/<user>/<repo>`, so you always know where a clone
is, and two repos with the same name from different users never collide.

```console
~ $ ghclone https://github.com/octocat/hello-world
Cloning into '/home/you/Development/github.com/octocat/hello-world'...
~/Development/github.com/octocat/hello-world $
```

Run it again for a repo you already have and it skips the clone and just
takes you there. It doesn't `git pull`.

```console
~ $ ghclone git@github.com:octocat/hello-world.git
Directory already exists: /home/you/Development/github.com/octocat/hello-world
~/Development/github.com/octocat/hello-world $
```

**URLs it accepts**: paste the repo URL itself. The URL is passed to
`git clone` unchanged, so an `ssh` URL clones over ssh and an `https` URL over
https.

| URL | Works? |
| --- | --- |
| `https://github.com/octocat/hello-world` | ✅ |
| `https://github.com/octocat/hello-world.git` | ✅ |
| `git@github.com:octocat/hello-world.git` | ✅ |
| `https://github.com/octocat/hello-world/` (trailing slash) | ❌ |
| `https://github.com/octocat/hello-world/tree/main` | ❌ |
| `octocat/hello-world` (shorthand) | ❌ |

When it can't read a URL it prints
`Error: Could not parse GitHub URL: <url>` and does nothing.

**Change where repos go** by setting `GHCLONE_ROOT`, e.g. in `~/.zshrc`:

```sh
export GHCLONE_ROOT="$HOME/code"   # -> ~/code/<user>/<repo>
```

### Session helpers: one session per folder

The Zellij and Herdr helpers work the same way, with matching names: `zl*`
for Zellij and `hr*` for Herdr. The idea is **one session per project
folder, named after the folder**. `cd` into a project, type `zl` or `hr`,
and you're back where you left off. If there's no session yet, a new one is
created.

```console
~/Development/github.com/cleanunicorn/local-config $ hr
# no "local-config" session yet -> starts one

~/Development/github.com/cleanunicorn/local-config $ hr
Session "local-config" exists. Attach/restore? [Y/n]
# Enter -> back into it. n -> "Aborted."
```

Things to know:

- **The session name is just the folder name**, not the full path. So
  `~/work/api` and `~/personal/api` both map to a session called `api`.
  Pass a name to tell them apart: `hr work-api`.
- **No nesting.** Inside a session, `zl`/`zla` and `hr`/`hra` refuse to run
  and print `Already inside a Zellij session.` or
  `Already inside a Herdr session.`.
- **The pickers use [fzf](https://github.com/junegunn/fzf).** Type to
  filter, arrow keys to move, Enter to choose, Esc to cancel. Cancelling
  does nothing.

  ```text
  > blo
    1/4 ─────────────────
  > blog
  ```

- **Stopping a session is not the same as deleting it.** The two tools
  word it slightly differently:

  |  | Zellij | Herdr |
  | --- | --- | --- |
  | Close the session, keep it to come back to later | **kill** (`zlk`): it becomes *exited*, and attaching resurrects it | **stop** (`hrk`): it becomes *stopped*, and attaching restores it |
  | Remove it for good, no undo | **delete** (`zld`, `zldx`) | **delete** (`hrd`, `hrdx`) |

### Zellij

*`zsh/zellij.zsh`. Needs `zellij` and `fzf`. `zlh` prints a summary in the
terminal.*

#### `zl [name]`

Open the session for this folder, or `name` if you give one.

- No session with that name → creates it and attaches.
- A session exists, running or exited → asks
  `Session "<name>" exists. Attach/resurrect? [Y/n]`. Enter attaches, and
  brings an exited session back to life. `n` prints `Aborted.`.

```console
~/projects/blog $ zl            # session "blog"
~/projects/blog $ zl scratch    # session "scratch", whatever folder you're in
```

#### `zla`

Pick any session from a list (running or exited) and attach to it. Handy
when you're not in the project folder.

#### `zlk`

Pick a session from a list and **kill** it. It stops running but Zellij keeps
its layout, so `zl`/`zla` can resurrect it later. The list shows every
session, including ones already exited; pick a running one.

#### `zld`

**Delete every exited session**, with no confirmation. Running sessions are
left alone. Use it to clear out the list. This one is a plain alias for
`zellij delete-all-sessions --yes`.

#### `zldx <name>`

**Delete one exited session** by name. Zellij refuses if it's still running;
kill it first with `zlk`.

```sh
zldx old-experiment
```

> Never add `-f`/`--force` to Zellij's delete commands. That kills running
> sessions before deleting them, with no undo. These helpers never use it.

### Herdr

*`zsh/herdr.zsh`. Needs `herdr`, `jq` and `fzf`. `hrh` prints a summary in
the terminal.*

Herdr always has a built-in session called `default`. The helpers leave it
out of the attach and delete lists so you don't touch it by accident.
`hrk` does list it while it's running.

#### `hr [name]`

Open the session for this folder, or `name` if you give one.

- No session with that name → creates it (`herdr --session <name>`).
- A session exists, running or stopped → asks
  `Session "<name>" exists. Attach/restore? [Y/n]`. Enter attaches, and
  restores a stopped session. `n` prints `Aborted.`.

```console
~/projects/blog $ hr            # session "blog"
~/projects/blog $ hr scratch    # session "scratch", whatever folder you're in
```

#### `hra`

Pick a session from a list (running and stopped, without `default`) and
attach to it. If you have no sessions yet, it acts like `hr` and starts one
for the current folder.

#### `hrk`

Pick a **running** session and **stop** it. Herdr saves its state, so
`hr`/`hra` can restore it later. Only running sessions are listed; with none,
it prints `No running Herdr sessions.`.

#### `hrd`

**Delete every stopped session** for good, with no confirmation. Running
sessions and `default` are left alone. With nothing to delete, it prints
`No stopped Herdr sessions.`. If any deletion fails, the rest still go ahead
and the command exits with status 1.

#### `hrdx <name>`

**Delete one stopped session** by name, for good.

```console
$ hrdx old-experiment
$ hrdx
Usage: hrdx <name>
```

## License

MIT
