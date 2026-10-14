# Box setup

Scripts that rebuild the box after an upgrade or wipe.

- `install.sh` installs Node, T3 Code, the agent CLIs and their plugins, then brings up Tailscale.
- `auth.sh` walks through logging in to each tool.
- `lib.sh` holds shared helpers for both scripts.
- `bin/tailscale-ensure.sh` starts tailscaled with state in `/workspace/.tailscale` and joins the tailnet as `x`.
- `bin/tailscale-watchdog.sh` restarts Tailscale if it drops.
- `bin/t3-serve-ensure.sh` starts `t3 serve --tailscale-serve` if it is not running.
- `bin/tailscale-autostart.sh` is the shell start hook that runs the two ensure scripts.

On the box, the files in `/workspace` are symlinks to this folder, so the `~/.bashrc` and `~/.profile` hooks keep working.
No secrets or Tailscale state live here.
