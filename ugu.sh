#! /bin/bash
# ugu - Script to update Ubuntu system and reduce wait.

# Copyright (c) 2019-2025 Maulik Mistry mistry01@gmail.com
# Reference: https://gitlab.freedesktop.org/drm/intel/-/issues/5455
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0

# License: BSD License 2.0
# Copyright (c) 2023–2025, Maulik Mistry
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

update_firefox_if_needed() {
  FIREFOX_DIR="$HOME/my_applications/firefox"
  FIREFOX_BIN="$FIREFOX_DIR/firefox"
  TMPDIR="/tmp"
  DOWNLOAD_PAGE_URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US"

  # Get current version
  if [[ ! -x "$FIREFOX_BIN" ]]; then
    echo "Firefox binary not found at $FIREFOX_BIN"
    return 1
  fi
  current_version="$($FIREFOX_BIN --version | awk '{print $3}')"

  # Get latest version URL
  html=$(curl -s "$DOWNLOAD_PAGE_URL")
  latest_url=$(echo "$html" | grep -oP 'https://download-installer\.cdn\.mozilla\.net[^"]+\.tar\.xz')
  latest_version=$(basename "$latest_url" | sed -E 's/^firefox-([0-9.]+)\.tar\.xz$/\1/')

  # Function to compare versions using sort -V
  version_gt() {
    [[ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" ]]
  }

  if version_gt "$latest_version" "$current_version"; then
    echo "Updating Firefox: $current_version → $latest_version"
    #cd "$TMPDIR" || return 1
    #curl -LO "$latest_url"
    #tarball=$(basename "$latest_url")

    #if ! command -v extract &>/dev/null; then
    #  echo "Missing 'extract' function or command"
    #  return 1
    #fi

    #extract "$tarball" || return 1

    # Backup current
    #timestamp=$(date +%s)
    #mv "$FIREFOX_DIR" "$TMPDIR/firefox-backup-$timestamp"
    #mv "$TMPDIR/firefox" "$FIREFOX_DIR"

    echo "Firefox updated to version $latest_version"
  else
    echo "Firefox is up to date (version $current_version)."
  fi
}

update_firefox_if_needed

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source ${SCRIPT_DIR}/bash_color_printf.sh

messenger_std "Updating snaps. . .";
# Split this out into a function, background process, and capture the output
# https://stackoverflow.com/questions/3096560/fork-and-exec-in-bash
# https://stackoverflow.com/questions/20017804/bash-capture-output-of-command-run-in-background
sudo snap refresh
messenger_end "Done.";
linefeed

#messenger_std "Clearing mandb files for faster post-install. . .";
#sudo systemctl start man-db
#messenger_end "Done.";
#linefeed

messenger_std "Updating packages. . .";
#sudo nala fetch --fetches 8 --country US
#sudo nala upgrade
#packages=$(sudo apt-fast update | tail -n 100)
#messenger_end "${packages}"
#sudo apt update |& tee /dev/tty
sudo apt update
messenger_end "Done.";
linefeed

if [[ ${packages} != "All packages are up to date."  ]]; then
  messenger_std "Upgrading. . .";
  #sudo apt-fast full-upgrade
  sudo apt full-upgrade
  no_issue=$?
  if [[ ${no_issue} -ne 0  ]]; then
    exit ${no_issue}
  else
    linefeed
    messenger_std "Cleaning installed packages. . .";
    sudo apt clean
    messenger_end "Done.";
    linefeed
  fi
fi

#messenger_std "Finding firmware updates...";
# No "sudo" needed
#fwupdmgr get-updates
# Manual for now
#fwupdmgr updates

messenger_end "Script done.";

#messenger_std "Updating flatpak. . .";
#flatpak update

# Per previous successes with man updates to delay stalling
#printf "\033[0;31mChecking for updates. . .\033[0m\n"
#has_updates=`sudo nala -o Acquire::ForceIPv4=true -o Acquire::https=true update`
#issue_found=$?

#if [[ ${issue_found} -ne 0  ]]; then
#  printf "\n\033[0;31m${has_updates}\033[0m\n"
#fi

#if [[ "${has_updates}" == *"Failed to fetch"* ]]; then
#  printf "\n\033[0;31mNetwork error.\033[0m\n"
#elif [[ "${has_updates}" != *"All packages are up to date."* ]]; then
 #  mandb -q
#  sudo runuser -u man -- mandb -q
#  printf "\n\033[0;31mList of packages to update. . .\033[0m\n";
#  nala list --upgradable
#  printf "\n\033[0;31mUpgrading. . .\033[0m\n"
#  sudo nala -o Acquire::ForceIPv4=true -o Acquire::https=true full-upgrade
#else
#  printf "\n\033[0;32mAll packages are up to date.\033[0m\n"
#fiI

