# shell-helpers

Small zsh helper functions I use every day.

## Install

```sh
git clone https://github.com/cleanunicorn/shell-helpers.git
echo 'source /path/to/shell-helpers/shell-helpers.zsh' >> ~/.zshrc
```

The entry point loads every module in `zsh/`. These are **sourced** functions,
not scripts, because some of them need to run in your current shell.

## Modules

| Module | Commands | Needs |
| --- | --- | --- |
| [`zsh/herdr.zsh`](zsh/herdr.zsh) | `hr`, `hra`, `hrk`, `hrd`, `hrdx`, `hrh` (help) | `herdr`, `jq`, `fzf` |
