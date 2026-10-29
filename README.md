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
2. **Loads the shell helpers.** Adds one line to `~/.zshrc` and `~/.bashrc`
   (for each shell that's installed) that sources `local-config.zsh`, which
   loads every file in `zsh/`.

Update later with `git pull`. Links pick up changes straight away; open a new
shell for helper changes.

## Layout

```
home/               mirrors $HOME; each file gets symlinked into place
  .config/herdr/config.toml
zsh/                shell helpers (zsh and bash), sourced by local-config.zsh
devbox/             devbox: Dockerfile, bin/, tests and the dv*/devbox_* functions
local-config.zsh    entry point for ~/.zshrc and ~/.bashrc
install.sh
```

To add a config file, put it under `home/` at the same path it has under
`$HOME` and run `./install.sh`. To add helpers, drop a `.zsh` file into `zsh/`;
keep it working in bash too and check with `bash tests/run.sh`, which runs the
helpers in bash and zsh against stub commands.

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
(`ghclone`, the attach commands) need to act on your current shell. They work
in zsh and bash.

| Command | Module | One-liner |
| --- | --- | --- |
| [`ghclone <url \| user/repo>`](#ghclone) | ghclone | Clone into `~/Development/github.com/<user>/<repo>` and `cd` there |
| [`p [query]`](#p-query) | Projects | Pick a project from a list and `cd` there |
| [`hp [query]`](#hp-query) | Projects | Pick a project, `cd` there and open its Herdr session |
| [`gup`](#gup) | Git | Switch to `main`/`master` and pull |
| [`gdone`](#gdone) | Git | After a merge: back to `main`/`master`, pull, delete the branch |
| [`upall`](#upall) | Updates | Update apt, the AI CLIs and their plugins, uv tools and Herdr |
| [`zl [name]`](#zl-name) | Zellij | Open the Zellij session for this folder |
| [`zla`](#zla) | Zellij | Pick a Zellij session from a list and attach |
| [`zlk`](#zlk) | Zellij | Pick a Zellij session and kill it (can be resurrected) |
| [`zld`](#zld) | Zellij | Delete every exited Zellij session |
| [`zldx <name>`](#zldx-name) | Zellij | Delete one exited Zellij session |
| [`zlh`](#zellij) | Zellij | Print the Zellij help |
| [`hr [name]`](#hr-name) | Herdr | Open the Herdr session for this folder |
| [`hra [query]`](#hra-query) | Herdr | Pick a Herdr session from a list and attach |
| [`hrk [query]`](#hrk-query) | Herdr | Pick a running Herdr session and stop it |
| [`hru [name…]`](#hru-name) | Herdr | Move running sessions to the new Herdr version without restarting them |
| [`hrd`](#hrd) | Herdr | Delete every stopped Herdr session |
| [`hrdx <name>`](#hrdx-name) | Herdr | Delete one stopped Herdr session |
| [`hrh`](#herdr) | Herdr | Print the Herdr help |
| [`dv [--docker]`](#devbox) | Devbox | Open this folder's long-lived Docker devbox (creates it on first use) |
| [`dvh`](#devbox) | Devbox | Print the devbox help (`dvk`, `dvp`, `dvr`, `dvd`, …) |

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

**What you can pass**: anything that points at a repo. Copy the address
bar from any page in the repo, a clone URL, or just `user/repo`. Extra path
(`/tree/main`, `/blob/main/README.md`, `/issues`), a trailing slash,
`?query` and `#fragment` are all ignored.

| Input | Clones |
| --- | --- |
| `octocat/hello-world` | `https://github.com/octocat/hello-world.git` |
| `github.com/octocat/hello-world` | `https://github.com/octocat/hello-world.git` |
| `https://github.com/octocat/hello-world` | `https://github.com/octocat/hello-world.git` |
| `https://github.com/octocat/hello-world/tree/main` | `https://github.com/octocat/hello-world.git` |
| `https://github.com/octocat/hello-world/blob/main/README.md` | `https://github.com/octocat/hello-world.git` |
| `https://github.com/octocat/hello-world?tab=readme-ov-file` | `https://github.com/octocat/hello-world.git` |
| `git@github.com:octocat/hello-world.git` | `git@github.com:octocat/hello-world.git` |
| `ssh://git@github.com/octocat/hello-world` | `git@github.com:octocat/hello-world.git` |

All of these land in `<root>/octocat/hello-world`.

**ssh or https?** A URL keeps the protocol it came with: an `ssh` URL clones
over ssh, anything else over https. The `user/repo` shorthand uses https by
default. To use ssh instead, set:

```sh
export GHCLONE_PROTOCOL=ssh
```

Not accepted: a user or org page with no repo (`https://github.com/octocat`)
and non-GitHub hosts. For those it prints
`Error: Could not parse GitHub URL: <input>` and does nothing.

The folder uses the capitalisation you typed. GitHub doesn't care about case,
but Linux does, so `octocat/Hello-World` and `octocat/hello-world` end up as
two different folders.

**Change where repos go** by setting `GHCLONE_ROOT`, e.g. in `~/.zshrc` or `~/.bashrc`:

```sh
export GHCLONE_ROOT="$HOME/code"   # -> ~/code/<user>/<repo>
```

### Projects

*`zsh/projects.zsh`. Needs `fzf`; `hp` also needs `herdr` and `jq`.*

#### `p [query]`

Pick a project from the folders under `~/Development/github.com` (the same
`$GHCLONE_ROOT` that `ghclone` uses) and `cd` into it. Words after `p` prefill
the search, and a single match is taken straight away.

```console
$ p canary        # one match -> straight into theralexis/canary
$ p               # browse every project
```

#### `hp [query]`

`p`, then `hr`: jump to the project and open its Herdr session in one go.

### Git

*`zsh/git.zsh`. Needs `git`; `gdone` also needs `gh` and `jq`.*

Both find the default branch from `origin/HEAD`, falling back to a local
`main` or `master`.

#### `gup`

Switch to the default branch and pull (pruning deleted remote branches).

#### `gdone`

Run it on a feature branch once its PR is merged. It switches to the default
branch, pulls, and deletes the branch. Squash and rebase merges are caught by
asking GitHub; the branch is only deleted if its PR is merged and has exactly
the commits on your local branch. Anything else keeps the branch and says so.

### Updates

*`zsh/update.zsh`.*

#### `upall`

Update everything in one go: `apt update` and `upgrade -y` (asks for your
sudo password), `claude update` and your user-scope Claude plugins, `codex`,
`opencode`, `pi`, `cctop`, every `uv tool`, then `herdr update --handoff` and
`hru` so running Herdr sessions move to the new version without restarting.
Tools that aren't installed are skipped. A failing step doesn't stop the rest;
the failures are listed at the end. Run it outside Herdr.

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

*`zsh/herdr.zsh`. Needs `herdr`, `jq` and `fzf`; in bash, `hru` also needs
`python3` to talk to the Herdr sockets. `hrh` prints a summary in the
terminal.*

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

#### `hra [query]`

Pick a session from a list (running and stopped, without `default`) and
attach to it. If you have no sessions yet, it acts like `hr` and starts one
for the current folder.

Words after `hra` prefill the search, like `p`: `hra canary`. A single
match is taken immediately; no matches means nothing is attached.

#### `hrk [query]`

Pick a **running** session and **stop** it. Herdr saves its state, so
`hr`/`hra` can restore it later. Only running sessions are listed; with none,
it prints `No running Herdr sessions.`.

Words after `hrk` prefill the search: `hrk canary`. A single match is
stopped immediately; no matches means nothing is stopped.

#### `hru [name…]`

After `herdr update`, running servers keep the old version until they
restart, and restarting closes their panes and agents. `hru` instead asks each
old server to **hand off its live panes** to the installed binary (Herdr's
experimental live handoff, the same thing `herdr update --handoff` does). Shells,
agents and dev servers keep running. A client attached with `hr` or `hra`
reconnects on its own; one started with plain `herdr` exits and you run it
again.

With no names it covers every running session still on an older version,
`default` included; pass names to do only those. It lists what it will do and
asks first. Sessions already on the current version are skipped, and a server
too old to hand off is reported so you can stop and reattach it instead. Run
it outside Herdr.

```console
$ hru canary
  canary  v0.9.3 -> v0.9.4
Hand off these sessions to v0.9.4? Panes keep running. [y/N] y
canary: handing off...
canary: now on v0.9.4
```

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

### Devbox

*`zsh/devbox.zsh`, loading `devbox/devbox.zsh`. Needs `docker`. Linux only.
`dvh` prints a summary in the terminal. More in [devbox/README.md](devbox/README.md).*

One long-lived container per project folder, built from
[`devbox/Dockerfile`](devbox/Dockerfile), with Claude Code, Node 22, `gh` and
Herdr installed. The folder is mounted at `/workspace`, and the container's
home lives on its own volume, so logins and history survive a rebuild.

```console
$ dvb                          # build the image: once, and after the Dockerfile changes
~/projects/blog $ dv           # create or start this folder's devbox and open a shell
~/projects/blog $ dvp 5173     # forward devbox:5173 to localhost:5173
```

The short `dv*` names follow the `hr*`/`zl*` pattern: `dv` opens the shell,
`dvk` stops (keeps) it, `dvd` deletes it, `dvh` prints the help. Each one is
the same as its long `devbox_*` name, which still works.

| Short | Long | What it does |
| --- | --- | --- |
| `dv [--docker]` | `devbox_shell` | Create or start this folder's devbox and open a shell (`--docker`: give it the host's Docker daemon) |
| `dvk` | `devbox_stop` | Stop it; `dv` starts it again |
| `dvp [--lan] CPORT [HPORT]` / `dvpl` / `dvpx HPORT` | `devbox_port` / `devbox_ports` / `devbox_unport` | Add, list and remove port forwards |
| `dvb [TAG]` | `devbox_build` | Rebuild the image |
| `dvr [--docker\|--no-docker] [--fresh-home [--yes]] [TAG]` | `devbox_recreate` | Move the devbox onto a new image, keeping its home volume |
| `dvu` | `devbox_update` | `git pull` this repo and reload the functions |
| `dvs [TAG]` | `devbox_save` | Snapshot the container as an image |
| `dvd [--purge]` | `devbox_rm` | Remove the devbox (`--purge` also deletes its home volume) |
| `dvt [--docker]` | `devbox_tmp` | Throwaway devbox, removed on exit |
| `dvh` | | Print this list in the terminal |

Full details, including what `--docker` allows and what survives a recreate,
are at the top of [`devbox/devbox.zsh`](devbox/devbox.zsh) and in
[devbox/README.md](devbox/README.md).

## License

MIT
