#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
# SPDX-License-Identifier: Apache-2.0
#
# ugu - Script to update Ubuntu system and reduce wait.
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702


# Using BASH_SOURCE for better path reliability in Bash
SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"
source "${SCRIPT_DIR}/vendor/tput_shell_colorize/tput_shell_colorize.sh"

# Avoid sudo use directly for more separating logic.
if [[ $EUID -eq 0 ]]; then
    echo "Error: Run this script as a normal user, NOT as root/sudo."
    exit 1
fi

APP_ROOT="$HOME/my_applications"
TMPDIR="/tmp"
SUDO_HEARTBEAT_PID=""

# Bash replacement for ZSH's 'is-at-least'
is_at_least() {
    # Returns 0 (true) if current version ($2) is >= latest version ($1)
    # Using sort -V (version sort) for robust numeric/dot comparison
    [[ "$1" == "$(echo -e "$1\n$2" | sort -V | head -n1)" ]]
}

retry_curl() {
    local url="$1"
    local attempts=3
    local count=0

    while [[ $count -lt $attempts ]]; do
        curl -LO "$url"
        if [[ $? -eq 0 ]]; then
            return 0
        fi
        count=$((count + 1))
        messenger_std "Retrying... ($count/$attempts)"
        sleep 2
    done

    messenger_std "Error: Failed to download $url after $attempts attempts."
    return 1
}

update_app() (
  local app_name="$1"
  local app_root="$2"
  local app_dir="$app_root"
  local app_bin

  # Locate binary
  if [[ -d "$app_dir/$app_name" ]]; then
    app_bin="$app_dir/$app_name/$app_name"
  elif [[ -d "$app_dir/bin/$app_name" ]]; then
    app_bin="$app_dir/bin/$app_name"
    messenger_std "The binary exists at $app_bin"
  else
    return 1
  fi

  local download_url="$3"
  local current_version="$($app_bin --version | awk '{print $NF}')"

  messenger_std "Checking for updates for $app_name..."
  local final_url
  final_url="$(curl -Ls -o /dev/null -w '%{url_effective}' "$download_url")"
  
  if [[ $? -ne 0 ]]; then
      messenger_std "Error: Failed to retrieve the final URL."
      return 1
  fi
  
  local latest_file="${final_url##*/}"
  local latest_version
  latest_version=$(echo "$latest_file" | grep -oE '[0-9]+(\.[0-9]+)+')

  if is_at_least "$latest_version" "$current_version"; then
    messenger_std "$app_name is up to date (version $current_version)."
    return 0
  fi

  messenger_std "Updating $app_name: $current_version → $latest_version"
  cd "$TMPDIR" || return 1
  retry_curl "$final_url" || return 1
  
  local tarball="${final_url##*/}"
  
  mkdir -p "${tarball%.tar.*}" && 
    cd "${tarball%.tar.*}" || return 1
  
  tar -xf "$TMPDIR/$tarball" || return 1

  local timestamp
  timestamp="$(date +%s)"

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
    echo "Initializing temporary administrative access for system updates..."

    # Prompts for password ONCE right here
    if ! sudo -v; then
        echo "Sudo authentication failed. Aborting."
        exit 1
    fi
    
    # Starts the background keeper loop
    while true; do 
      sudo -v; 
      sleep 60; 
    done 2>/dev/null &
    

    SUDO_HEARTBEAT_PID=$!
    messenger_std "Privileges verified. Sudo heartbeat active (PID: ${SUDO_HEARTBEAT_PID})."

}

end_sudo_run() {
    if [ -n "${SUDO_HEARTBEAT_PID}" ] && kill -0 "${SUDO_HEARTBEAT_PID}" 2>/dev/null; then
        kill "${SUDO_HEARTBEAT_PID}" 2>/dev/null
        wait "${SUDO_HEARTBEAT_PID}" 2>/dev/null
    fi
}

# -------------------------------------------------------
# Optional updates (uncomment as needed)

messenger_std "Starting optional updates..."
linefeed

update_app "firefox" "$APP_ROOT" \
 "https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US" &

#update_app "thunderbird" "$APP_ROOT" \
# "https://download.mozilla.org/?product=thunderbird-latest-ssl&os=linux64&lang=en-US" &

update_app "zen" $APP_ROOT \
 "https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz" &

update_app "nvim-linux-x86_64" "$APP_ROOT" \
 "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" &

wait # Let asynchronous application updates finalize

#messenger_std "Finding firmware updates..."
# No "sudo" needed
#fwupdmgr get-updates
# Manual for now
#fwupdmgr update

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

messenger_end "Done with tooling updates."
linefeed

# -------------------------------------------------------

# Start a sudo heartbeat for processes that need it
check_sudo_run

messenger_std "Updating snaps. . ."
sudo snap refresh
python3 "$SCRIPT_DIR/vendor/snap_cleanup/snap_cleanup.py"
linefeed
messenger_end "Done."
linefeed

messenger_std "Updating packages. . ."
sudo apt-fast update
linefeed
messenger_end "Done."
linefeed

update_status=$?

if [[ $update_status -ne 0 ]]; then
  messenger_std "Failed to update package lists."
  exit "$update_status"
fi

# Count upgradable packages
upgrade_count=$(apt list --upgradable 2>/dev/null | grep -vc '^Listing')

if [[ $upgrade_count -gt 0 ]]; then
  messenger_std "Upgrading. . ."
  sudo apt-fast full-upgrade

  if [[ $? -ne 0 ]]; then
    messenger_std "Failure during apt full-upgrade."
    exit 1
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
