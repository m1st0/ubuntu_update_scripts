<!--
SPDX-FileCopyrightText: Copyright (c) 2017–2026 Maulik Mistry
SPDX-License-Identifier: Apache-2.0
-->
# UGU – Ubuntu Grab Updates

This project provides a ZSH tool that updates an Ubuntu system in parallel. Each update runs in its own tmux window with its own terminal, and a live dashboard shows progress for all of them.

Copyright © 2017–2026 Maulik Mistry

This project is licensed under Apache License 2.0. See the [LICENSE.txt](LICENSE.txt) file for details.

Please share support: 
- [PayPal](https://www.paypal.com/paypalme/m1st0)
- [Venmo](https://venmo.com/code?user_id=3319592654995456106&created=1753283702)

## Why this?

A demonstration of system updates, package management, and scripting in ZSH, valuable for Ubuntu users and developers alike.

Many Ubuntu users face challenges with automatic updates, especially when using Firefox Snap or Deb installations. 
This script offers a reliable solution for those who prefer manual installations or need to bypass restrictions imposed by certain distributions.

## Features

- Updates run in parallel, each in its own tmux window (its own pty), so one slow or failing update never blocks the others
- Live dashboard in window 0: animated progress bars, per-worker timers, the last line of each worker's terminal, and an activity feed
- Menu to choose what to run (powered by gum), or flags to skip it
- Every worker also runs on its own, for example `./ugu_system.zsh`
- Exampled upgrades via release URLs under `$HOME/my_applications/$app_name`, with real download progress and an automatic backup of the previous install
- Works well for distros that block applications like Firefox in Snap or Deb, or preferring a manual install
- Exampled AstroNvim configuration, neovim, fwupdmgr, flatpak, rust toolchain, and uv upgrades (fwupdmgr and flatpak are optional and can stay commented out)
- Snap refresh is run first to prevent delays
- APT update/upgrade, which continues with the existing package lists if the index update fails
- Each worker asks for its own sudo password in its own window and keeps it fresh during long upgrades
- Unattended (cron) runs fail fast instead of waiting for a password nobody can type
- Optional cleanup steps
- A full log of each worker's terminal output, kept when something fails

## Requirements

- Ubuntu with ZSH
- `tmux`, [gum](https://github.com/charmbracelet/gum#installation), and `apt-fast` (UGU checks for these at startup)
- `sudo`, `snap`, and `python3` for system updates
- `curl`, `jq`, `tar`, `awk`, and `grep` for application updates
- `rustup`, `uv`, and `git` for development tool updates (a missing tool is skipped, not a failure)
- `fwupdmgr` and `flatpak` only if you enable those updates (a missing tool is skipped, not a failure)

## Setup and Use

1. Clone this repo and make scripts executable:

    ```
    git clone --recurse-submodules https://github.com/m1st0/ugu.git ugu
    cd ugu
    ```

    If the project was already cloned without its submodules:

    ```
    git submodule update --init --recursive
    ```

2. Make the desired scripts executable:

    ```
    chmod +x ugu.zsh ugu_*.zsh
    ```

3. Run the script as your normal user, not as root:

    ```zsh
    ./ugu.zsh
    ```

### Options

| Command | What it does |
| --- | --- |
| `./ugu.zsh` | Shows a menu in a terminal. With no terminal, runs everything. |
| `./ugu.zsh -a` | Runs everything now, with no menu. |
| `./ugu.zsh -o system,tools` | Runs only the named workers, with no menu. |
| `./ugu.zsh -m` | Always shows the menu. |
| `./ugu.zsh -y` | Answers apt prompts automatically. |

Workers: `firefox`, `thunderbird`, `zen`, `system`, `tools`.

The menu has an "Everything (and stop asking)" entry. It creates `~/.config/ugu/skip-menu`, and later runs go straight to everything. Use `-m` or delete that file to bring the menu back. Setting `UGU_ALWAYS_ALL=1` does the same.

### Dashboard and tmux

UGU runs on its own private tmux server, so your own tmux sessions and configuration are not touched.

- Press `1` to `9` in the dashboard, or `Ctrl-b` then a number, to open a worker's terminal. `Ctrl-b 0` returns to the dashboard. Clicking the window tabs also works.
- When a worker needs you (a sudo password or a yes/no question), the dashboard switches to its window and switches back when you have answered.
- When all workers finish, press `q` or Enter in the dashboard to close it and print the summary. Finished windows stay open until then.
- If you detach early you can reattach, leave it running in the background, or kill it.

### Running a worker alone

Each worker script runs by itself with its own progress output, no tmux needed:

```zsh
./ugu_system.zsh
./ugu_tools.zsh
UGU_ASSUME_YES=1 ./ugu_system.zsh
```

### Unattended runs (cron)

With no terminal attached, UGU runs headless, runs everything, and answers apt prompts with yes. It exits with status 1 if any worker fails, and prints the report and log location.

System updates need root, and nobody can type a password. The system worker therefore requires `sudo -n -v` to succeed and otherwise fails right away with a clear message. The other workers are not affected. `UGU_ASSUME_YES=0` disables the automatic yes, but apt will then wait for an answer that never comes. Apt can also ask about changed configuration files during an upgrade, even with `-y`.

### Logs

Each worker's terminal output is logged under `$XDG_RUNTIME_DIR/ugu-UID-PID/logs`. The directory is removed when every worker succeeds, and kept when one fails (the path is printed). The logs contain terminal color codes and carriage returns. View them with `less -r`, or in a terminal with `cat`.

## Mozilla (and Zen) Update Strategy

Unlike Snap or Apt installs, this script checks Mozilla’s (Zen's) release site and updates your manually installed Firefox/Thunderbird/Zen if needed. There used to be issues with the Snap and Apt install changes. I have opted for a manual Mozilla product installation, which allows for custom update checks.

Your custom Firefox/Thunderbird/Zen should previously be installed into unless you want to update the script:

```
$HOME/my_applications/firefox/
$HOME/my_applications/thunderbird/
$HOME/my_applications/zen/
```

The script will:

- Detect the current version a binary
- Compare it to online Mozilla or Github versions per respective binaries
- Download the new release with live progress, check the archive layout, and unpack it to a staging directory
- Move the old install to `$HOME/my_applications/APP.backup-TIMESTAMP` and put the new one in place, restoring the old one if that fails

Backups are not removed automatically, so delete old `.backup-*` directories when you no longer need them.

If **AppArmor** complains about your custom use of Mozilla apps, check out my [apparmor_customizations](https://github.com/m1st0/apparmor_customization). 

## Adding a worker

1. Create `ugu_NAME.zsh` that sources `ugu_common.zsh`, defines `ugu_NAME_main`, and ends with `ugu_run_worker NAME ugu_NAME_main; exit $?`. Copy `ugu_tools.zsh` as a starting point.
2. Report progress with `ugu_progress NAME PERCENT "Stage" "Message"`. Return non-zero from the main function on failure.
3. Add `NAME` to the `workers` list in `ugu.zsh` (and to the menu's "Pick workers" list).

Workers report through a small state file, so the dashboard never has to guess from terminal text.
