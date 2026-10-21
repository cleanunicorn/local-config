# Devbox helpers (dv, dvp, … / devbox_shell, devbox_port, …): one long-lived Docker
# container per project folder. The functions, Dockerfile and tests live in
# devbox/; see devbox/README.md.

DEVBOX_DIR="$LOCAL_CONFIG_DIR/devbox"
source "$DEVBOX_DIR/devbox.zsh"
