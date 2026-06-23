#! /usr/bin/zsh
# ugu - Script to update Ubuntu system and reduce wait.

# Copyright (c) 2019-2026 Maulik Mistry mistry01@gmail.com
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
# License: BSD License 2.0


SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/zsh_color_print.zsh"

# Avoid sudo use directly for more separating logic.
if (( EUID == 0 )); then
    messenger_std "Error: Run this script as a normal user, NOT as root/sudo."
    exit 1
fi

APP_ROOT="$HOME/my_applications/$app_name"
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

update_app() {
  local app_name="$1"
  local app_root="$2" # Accept APP_ROOT as an argument
  local app_dir="$app_root" # Use the passed APP_ROOT
  local app_bin

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

  # Follow redirect and get final URL
  messenger_std "Curling away to check for updates..."
  local final_url="$(curl -Ls -o /dev/null -w '%{url_effective}' "$download_url")"
  if [[ $? -ne 0 ]]; then
      messenger_std "Error: Failed to retrieve the final URL from $download_url."
      return 1
  fi
  local latest_file="${final_url##*/}"
  local latest_version="$(echo "$latest_file" | grep -oP '[0-9]+(\\.[0-9]+)+')"

  autoload -Uz is-at-least
  if is-at-least "$latest_version" "$current_version"; then
    messenger_std "$app_name is up to date (version $current_version)."
    return 0
  fi

  messenger_std "Updating $app_name: $current_version → $latest_version"
  cd "$TMPDIR" || return 1
  retry_curl "$final_url"
  if [[ $? -ne 0 ]]; then
    return 1  # Handle failure
  fi
  local tarball="${final_url##*/}"

  mkdir -p "${tarball%.tar.*}" && cd "${tarball%.tar.*}" || return 1
  tar -xf "$TMPDIR/$tarball" || return 1

  local timestamp="$(date +%s)"

  mv "$app_dir" "$TMPDIR/${app_name}-backup-$timestamp"
  mv "$TMPDIR/$app_name" "$app_dir"

  messenger_std "$app_name updated to version $latest_version"
}

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
  messenger_std "Privileges verified. Zsh heartbeat active (PID: ${SUDO_HEARTBEAT_PID})."
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
        
        messenger_end "Heartbeat stopped cleanly."
    fi
}

# -------------------------------------------------------
# Optional updates (uncomment as needed)

#messenger_std "Starting optional updates..."

#update_app "firefox" $APP_ROOT \
# "https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US"

#update_app "thunderbird" $APP_ROOT \
# "https://download.mozilla.org/?product=thunderbird-latest-ssl&os=linux64&lang=en-US"

#update_app "zen" $APP_ROOT \
# "https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz"

#update_app "nvim-linux-x86_64" \
# "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"

#messenger_std "Finding firmware updates..."
# No "sudo" needed
#fwupdmgr get-updates
# Manual for now
#fwupdmgr update

#messenger_std "Updating flatpak. . ."
#flatpak update

#messenger_std "Updating rust toolchain. . ."
#rustup update

#messenger_std "Updating uv. . ."
#uv self update

#messenger_std "Updating AstroNvim template configuration..."
#git -C $HOME/.config/nvim pull

#messenger_end "Done with optional updates."

# -------------------------------------------------------

# Start a sudo heartbeat for processes that need it
check_sudo_run

messenger_std "Updating snaps. . ."
sudo snap refresh
$SCRIPT_DIR/snap_cleanup.py
messenger_end "Done."
linefeed

messenger_std "Updating packages. . ."
sudo apt-fast update
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
  sudo apt clean
  messenger_end "Done."
  linefeed
else
  messenger_std "Nothing to upgrade."
fi

end_sudo_run
linefeed
messenger_end "Script done."
