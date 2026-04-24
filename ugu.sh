#!/bin/bash
# ugu - Script to update Ubuntu system and reduce wait.

# Copyright (c) 2019-2026 Maulik Mistry mistry01@gmail.com
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
# License: BSD License 2.0

# Using BASH_SOURCE for better path reliability in Bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${SCRIPT_DIR}/bash_color_printf.sh"

APP_ROOT="$HOME/my_applications/$app_name"
TMPDIR="/tmp"

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

update_app() {
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
  mkdir -p "${tarball%.tar.*}" && cd "${tarball%.tar.*}" || return 1
  tar -xf "$TMPDIR/$tarball" || return 1

  local timestamp
  timestamp="$(date +%s)"

  # Backup and replace
  mv "$app_dir" "$TMPDIR/${app_name}-backup-$timestamp"
  mv "$TMPDIR/$app_name" "$app_dir"

  messenger_std "$app_name updated to version $latest_version"
}

# --- Optional updates (uncomment as needed) ---
#update_app "firefox" "$APP_ROOT" \
# "https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US"

#update_app "thunderbird" "$APP_ROOT" \
# "https://download.mozilla.org/?product=thunderbird-latest-ssl&os=linux64&lang=en-US"

#update_app "zen" $APP_ROOT \
# "https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz"

#update_app "nvim-linux-x86_64" "$APP_ROOT" \
# "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"

#messenger_std "Finding firmware updates..."
# No "sudo" needed
#fwupdmgr get-updates
# Manual for now
#fwupdmgr updates

#messenger_std "Updating flatpak. . ."
#flatpak update

#messenger_std "Updating rust toolchain. . ."
#rustup update
# -------------------------------------------------------

messenger_std "Updating snaps. . ."
sudo snap refresh
python3 "$SCRIPT_DIR/snap_cleanup.py"
messenger_end "Done."
linefeed

messenger_std "Updating packages. . ."
sudo apt-fast update
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
  sudo apt clean
  messenger_end "Done."
  linefeed
else
  messenger_std "Nothing to upgrade."
fi

messenger_end "Script done."
