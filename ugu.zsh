#!/usr/bin/env zsh
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
# SPDX-License-Identifier: Apache-2.0
#
# ugu - Script to update Ubuntu system and reduce wait.
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702


SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/vendor/tput_shell_colorize/tput_shell_colorize.sh"

# Avoid sudo use directly for more separating logic.
if (( EUID == 0 )); then
    messenger_std "Error: Run this script as a normal user, NOT as root/sudo."
    exit 1
fi

APP_ROOT="$HOME/my_applications"
TMPDIR="/tmp"
SUDO_HEARTBEAT_PID=""

retry_curl() {
    local url="$1"
    local attempts=3
    local count=0

    while [[ $count -lt $attempts ]]; do
        curl -LO "$url"
        if [[ $? -eq 0 ]]; then
            return 0  # Success
        fi
        count=$((count + 1))
        messenger_std "Retrying... ($count/$attempts)"
        sleep 2  # Wait before retrying
    done

    messenger_std "Error: Failed to download $url after $attempts attempts."
    return 1  # Failure after retries
}

get_github_latest_version() {
  local repo="$1"
  local latest_version

  latest_version="$(curl -fsSL \
    "https://api.github.com/repos/$repo/releases/latest" |
    jq -r '.tag_name')"

  if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
    return 1
  fi

  # GitHub projects such as Neovim use tags like v0.11.3.
  latest_version="${latest_version#v}"

  print -r -- "$latest_version"
}

update_app() (
  local app_name="$1"
  local app_root="$2"
  local app_dir="$app_root"
  local app_bin

  if [[ -d "$app_dir/$app_name" ]]; then
    app_bin="$app_dir/$app_name/$app_name"
    messenger_std "The binary exists at $app_bin"
  elif [[ -d "$app_dir/bin/$app_name" ]]; then
    app_bin="$app_dir/bin/$app_name"
    messenger_std "The binary exists at $app_dir/bin/$app_name"
  else
    messenger_std "Cannot find the binary, returning"
    linefeed
    return 1
  fi

  local download_url="$3"
  local github_repo="$4"
  local current_version="$($app_bin --version | awk '{print $NF}')"
  local latest_version
  local final_url

  if [[ -n "$github_repo" ]]; then
    messenger_std "Checking GitHub for $app_name updates..."

    if ! latest_version="$(get_github_latest_version "$github_repo")"; then
      messenger_std "Error: Failed to retrieve the latest GitHub release for $app_name."
      return 1
    fi

    final_url="$download_url"
  else
    messenger_std "Curling away to check for $app_name updates..."

    if ! final_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$download_url")"; then
      messenger_std "Error: Failed to retrieve the final URL from $download_url."
      return 1
    fi

    local latest_file="${final_url##*/}"
    latest_version="$(print -r -- "$latest_file" | grep -oP '[0-9]+(\.[0-9]+)+')"
  fi  
  
  autoload -Uz is-at-least

  if is-at-least "$latest_version" "$current_version"; then
    messenger_std "$app_name is up to date (version $current_version)."
    linefeed
    return 0
  fi

  messenger_std "Updating $app_name: $current_version → $latest_version"

  cd "$TMPDIR" || return 1

  retry_curl "$final_url"
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  local tarball="${final_url##*/}"

  mkdir -p "${tarball%.tar.*}" &&
    cd "${tarball%.tar.*}" || return 1

  tar -xf "$TMPDIR/$tarball" || return 1

  local timestamp="$(date +%s)"

  if ! mv "$app_dir/$app_name" "$TMPDIR/${app_name}-backup-$timestamp"; then
    messenger_std "Error: Failed to back up $app_name."
    return 1
  fi

  if ! mv "$TMPDIR/${tarball%.tar.*}/$app_name" "$app_dir/$app_name"; then
    messenger_std "Error: Failed to install updated $app_name."
    return 1
  fi
  
  messenger_std "$app_name updated to version $latest_version"
  linefeed
)

check_sudo_run() {
  # prompt for sudo once; fail if user cancels
  if ! sudo -v; then
    messenger_end "Requires sudo privileges."
    exit 1
  fi

  # start background keep-alive to refresh the sudo timestamp
  while true; do
    sudo -v
    sleep 60
  done 2>/dev/null &

  SUDO_HEARTBEAT_PID=$!
  messenger_std "Privileges verified. Sudo heartbeat active (PID: ${SUDO_HEARTBEAT_PID})."
}

end_sudo_run() {
    # Check if the heartbeat PID exists and is actively running
    if [[ -n "${SUDO_HEARTBEAT_PID}" ]] && kill -0 "${SUDO_HEARTBEAT_PID}" 2>/dev/null; then
        messenger_std "Stopping sudo heartbeat loop (PID: ${SUDO_HEARTBEAT_PID})..."
        
        # Terminate the background loop
        kill "${SUDO_HEARTBEAT_PID}" 2>/dev/null
        
        # NOTE FOR ZSH: Zsh will complain if you try to 'wait' on a process 
        # that it knows was forcefully terminated, so redirect stderr here 
        # to keep the terminal perfectly pristine
        wait "${SUDO_HEARTBEAT_PID}" 2>/dev/null
        
        linefeed
        messenger_end "Heartbeat stopped cleanly."
        linefeed
    fi
}

# -------------------------------------------------------
# Optional updates (uncomment as needed)

messenger_std "Starting optional updates..."
linefeed

update_app "firefox" "$APP_ROOT" \
  "https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US" &

update_app "thunderbird" "$APP_ROOT" \
  "https://download.mozilla.org/?product=thunderbird-latest&os=linux64&lang=en-US" &

update_app "zen" "$APP_ROOT" \
  "https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz" \
  "zen-browser/desktop" &

#update_app "nvim" "$APP_ROOT" \
#  "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" \
#  "neovim/neovim" &

wait # Let asynchronous app updates finalize

#messenger_std "Finding firmware updates..."
# No "sudo" needed
#fwupdmgr get-updates
# Manual for now
#fwupdmgr update
#linefeed

#messenger_std "Updating flatpak. . ."
#flatpak update

messenger_std "Updating rust toolchain. . ."
rustup update
linefeed

messenger_std "Updating uv. . ."
uv self update
linefeed

messenger_std "Updating AstroNvim template configuration..."
git -C $HOME/.config/nvim pull
linefeed

messenger_end "Done with optional updates."
linefeed

# -------------------------------------------------------

# Start a sudo heartbeat for processes that need it
check_sudo_run

messenger_std "Updating snaps. . ."
sudo snap refresh
python3 $SCRIPT_DIR/vendor/snap_cleanup/snap_cleanup.py
linefeed
messenger_end "Done."
linefeed

messenger_std "Updating packages. . ."
sudo apt-fast update
linefeed
messenger_end "Done."
linefeed

update_status=$?

if (( $update_status != 0 )); then
  messenger_std "Failed to update package lists."
  exit $update_status
fi

# Grep counts non-matching lines, so 0 if no upgrades.
upgrade_count=$(apt list --upgradable 2>/dev/null | grep -vc '^Listing')

if (( $upgrade_count > 0 )); then
  messenger_std "Upgrading. . ."
  sudo apt-fast full-upgrade

  upgrade_exit_code=$?
  if (( $upgrade_exit_code != 0 )); then
    messenger_std "Failure to apt full-upgrade command."
    exit $upgrade_exit_code
  fi

  linefeed
  messenger_std "Cleaning out installed debs. . ."
  # Prevent apt lock.
  sleep 1
  sudo apt clean
  messenger_end "Done."
  linefeed
else
  messenger_std "Nothing to upgrade."
fi

end_sudo_run
messenger_end "Script done."
