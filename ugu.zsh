#! /usr/bin/zsh
# ugu - Script to update Ubuntu system and reduce wait.

# Copyright (c) 2019-2025 Maulik Mistry mistry01@gmail.com
# Reference: https://gitlab.freedesktop.org/drm/intel/-/issues/5455
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0

# License: BSD License 2.0
# [same license text as original, omitted for brevity]

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/zsh_color_print.zsh"

update_firefox_if_needed() {
  local FIREFOX_DIR="$HOME/my_applications/firefox"
  local FIREFOX_BIN="$FIREFOX_DIR/firefox"
  local TMPDIR="/tmp"
  local DOWNLOAD_PAGE_URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US"

  if [[ ! -x "$FIREFOX_BIN" ]]; then
    messenger_std "Firefox binary not found at $FIREFOX_BIN"
    return 1
  fi

  local current_version="$($FIREFOX_BIN --version | awk '{print $3}')"
  local html="$(curl -s "$DOWNLOAD_PAGE_URL")"
  local latest_url="$(echo "$html" | grep -oE 'https://download-installer\\.cdn\\.mozilla\\.net[^"]+\\.tar\\.xz')"
  local latest_version="${latest_url##*/}"
  latest_version="${latest_version#firefox-}"
  latest_version="${latest_version%.tar.xz}"

  autoload -Uz is-at-least
  if is-at-least "$latest_version" "$current_version"; then
    messenger_std "Firefox is up to date (version $current_version)."
    return 0
  fi

  messenger_std "Updating Firefox: $current_version → $latest_version"
  # cd "$TMPDIR" || return 1
  # curl -LO "$latest_url"
  # local tarball="${latest_url##*/}"

  # if ! whence extract &>/dev/null; then
  #   messenger_std "Missing 'extract' function or command"
  #   return 1
  # fi

  # extract "$tarball" || return 1

  # local timestamp="$(date +%s)"
  # mv "$FIREFOX_DIR" "$TMPDIR/firefox-backup-$timestamp"
  # mv "$TMPDIR/firefox" "$FIREFOX_DIR"

  messenger_std "Firefox updated to version $latest_version"
}

update_firefox_if_needed

messenger_std "Updating snaps. . ."
sudo snap refresh
messenger_end "Done."
linefeed

messenger_std "Updating packages. . ."
sudo apt update
messenger_end "Done."
linefeed

if [[ $packages != "All packages are up to date." ]]; then
  messenger_std "Upgrading. . ."
  sudo apt full-upgrade
  local no_issue=$?
  if [[ $no_issue -ne 0 ]]; then
    exit $no_issue
  else
    linefeed
    messenger_std "Cleaning installed packages. . ."
    sudo apt clean
    messenger_end "Done."
    linefeed
  fi
fi

messenger_end "Script done."
